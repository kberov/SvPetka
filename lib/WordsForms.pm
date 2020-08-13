#!/usr/bin/env perl
package WordsForms;

use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);

use FindBin qw($RealBin);
use IO::Dir;
use Mojo::DOM;
use YAML::XS;
use Mojo::Collection 'c';
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);
use Mojo::IOLoop::Subprocess;
binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';
no warnings 'redefine';
local *Data::Dumper::qquote  = sub {qq["${\(shift)}"]};
local $Data::Dumper::Useperl = 1;

has debug    => 0;
has data_dir => sub { path("$RealBin/../data")->realpath };

# Разстояния: ordered by closest place same book,then orthography, then monastery then time, . All from Evtimij
# Пример: http://histdict.uni-sofia.bg/textcorpus/show/doc_155
has distances => sub {
  c(
    'doc_155', 'doc_156', 'doc_214', 'doc_212', 'doc_216', 'doc_217', 'doc_219',
    'doc_220', 'doc_221', 'doc_222', 'doc_223', 'doc_225', 'doc_157', 'doc_213',
    'doc_158', 'doc_159', 'doc_197', 'doc_202', 'doc_205', 'doc_211',

  );
};

# Близост по разстояния: най-малкѿо число е най-близкия документ.
has closeness => sub($me) {
  my $closest = {};
  $me->distances->each(sub ($e, $num) { $closest->{$e} = $num });
  return $closest;
};

# бꙋкви за създаване на израз ѿ примерна дума и търсене
has bukvi => sub {
  my $l = {
    'о'  => "[оѡꙫѻꙩ]",
    'ѡ'  => "[оѡꙫѻꙩ]",
    'ꙫ'  => "[оѡꙫѻꙩ]",
    'ѻ'  => "[оѡꙫѻꙩ]",
    'ꙩ'  => "[оѡꙫѻꙩ]",
    'ѿ'  => "(?:ѿ|[оѡꙫѻꙩ]т)",
    'ы'  => "[ыꙑ]",
    'ыи' => "[ыꙑ]и?",
    'ꙑ'  => "[ыꙑ]",
    'ꙑи' => "[ыꙑ]и?",
    'ъ'  => "[ъьꙿ]?",
    'ь'  => "[ьъꙿ]?",
    'ꙿ'  => "[ꙿьъ]?",
    'е'  => "[еєѥ]",
    'є'  => "[єеѥ]",
    'ѥ'  => "[ѥеє]",
    'ѧ'  => "[ѧꙙ]",
    'ꙙ'  => "[ꙙѧ]",
    'и'  => "[ийії]",
    'й'  => "[йиії]",
    'і'  => "[іїий]",
    'ї'  => "[їіий]",
    'ꙗ'  => "(?:ꙗ|їа|іа|иа)",
    'їа' => "(?:ꙗ|їа|іа|иа)",
    'іа' => "(?:ꙗ|їа|іа|иа)",
    'иа' => "(?:ꙗ|їа|іа|иа)",
    'ꙋ'  => '(?:ꙋ|ѹ|у|оу)',
    'ѹ'  => '(?:ѹ|ꙋ|у|оу)',
    'у'  => '(?:у|ꙋ|ѹ|оу)',
    'ѫ'  => '[ѫуꙋ]',
    'їе' => '(?:їе|ѥ|іе)',
  };
  my @glasni = keys %$l;
  $l = {'з' => "[зѕꙁꙃ]", 'ѕ' => "[ѕзꙁꙃ]", 'ꙁ' => "[ꙁзѕꙃ]", 'ꙃ' => "[ꙃзѕꙁ]", %$l};

  my @syglasni = (qw(б в г д ж к л м н п р с т ф х ц ч ш щ з ѕ ꙁ ꙃ));
  for my $b (@syglasni) {
    for my $y (@glasni) {
      $l->{"$b$y"} = "$b$l->{$y}";
      $l->{$b} = "$b$l->{ъ}";
    }
  }

  $l->{'н'} = "[eьъꙿ]?н$l->{ъ}";

  #$l->{' '} = '\s*?';
  return $l;
};

sub log ($self, $thing) {
  return unless ($self->debug);
  say STDERR ((ref $thing ? dumper($thing) : $thing),
    ' at ' . (join ':', (caller(1))[1, 2]));
}

sub make_word_regex ($self, $w) {
  state $l = $self->bukvi;

  # longer keys first
  state $rex_keys = [sort { length($b) <=> length($a) } sort keys %$l];

  # build the regex for this word
  state $rex_keys_rex = join '|', @$rex_keys;

  # "же" и "сѧ" са изключения и може и дa не се търси за тях
  my ($zese) = $w =~ /\s+(же|с$l->{ѧ})$/;
  if ($zese) {
    $w =~ s/$zese//;
  }
  my $m   = '';
  my $rex = $w =~ s/($rex_keys_rex)/
        (($m = lc $1) && ($l->{$m} ? $l->{$m} : $m))
        /xiger;
  if ($zese) {
    $rex =~ s/\s+$/\\s*?/;
    $rex = qr/$rex(?:$zese)?/i;
  }
  else {
    $rex = qr/$rex/i;
  }
  $self->log("$w:/$rex/");

  return $rex;
}

has file_to_check => sub {
  my $file = path("$RealBin/../texts/Prostranno-Evt-ZogrSb-chist.txt")->realpath;
  -f $file && -s $file || die "The file $file is not a file or it is empty";
  return $file;
};

# Редове с думи, които взимаме ѿ файла, който ще проверяваме, ако не са подадени на
# реда.
has word_lines => sub {
  return [split '\n+', decode(utf8 => $_[0]->file_to_check->slurp)];
};

has source_file_lines => sub {
  [split '\n+', decode(utf8 => $_[0]->source_file->slurp)];
};

# files to search for word_lines
has files_contents => sub {
  my $from_dir = "$RealBin/../histdict_evt_docs";
  $_[0]->distances->map(sub {
    my $doc = path($from_dir, "${_}_clean")->realpath;
    die "!!Document '$doc' was not found on the file system!!!" unless -f $doc && -s $doc;
    decode utf8 => $doc->slurp;
  });
};

has source_file => sub { path("$RealBin/../texts/Petka_NOVA_chist.txt")->realpath; };

# Default range of word_lines to check.
# 0 .. the word_lines
has range => sub {
  [0, @{$_[0]->source_file_lines} - 1];
};


sub diff ($self, $source, $changed) {
  return if ($source eq $changed);
  return 1;
}

has changed_words_file => sub { path($_[0]->data_dir, 'changed_words.yml') };

# loads a potentialy existing on disk structure with found words and returns it.
has changed_words => sub {
  my $chngd_wrds = $_[0]->changed_words_file;
  my $words      = [];
  if (-f $chngd_wrds && -s $chngd_wrds) {
    my $words = YAML::XS::Load($chngd_wrds->slurp);
    return $words;
  }
  return [];
};

has unique_changed_words => sub {
  my $unique_words = {};
  for my $w (@{$_[0]->changed_words}) {

    # my $key = sprintf('%03d', $w->{РедВРъкописа}) . "|$w->{Източник}=>$w->{Променена}";
    my $key = lc $w->{Променена};
    $unique_words->{$key} = $w unless exists $unique_words->{$key};
  }
  return $unique_words;
};

# Проверява в changed_words дали тази дума,ѿ това място - същата инстанция е
# вече добавена във changed_words и ако е така връща true. Как? Проверява дали
# всички свойства описващи думата съвпадат: ред регулярен израз, съкращенѥ,
# променен вид…
sub is_word_already_added ($self, $word) {
  my $words        = $self->changed_words;
  my $words_length = @$words;

  for my $i (0 .. $words_length - 1) {
    my $added
      = $word->{Източник} eq $words->[$i]{Източник}
      && $word->{Променена} eq $words->[$i]{Променена}
      && $word->{ИзразЗаТърсене} eq $words->[$i]{ИзразЗаТърсене}
      && $word->{РедВРъкописа} eq $words->[$i]{РедВРъкописа};
    if ($added) {
      return $added;
    }
  }
  return 0;
}

# Проверява в changed_words дали думата вече не е срещаната и и връща индеѯа на
# срещната дума или големината на масива. Така винаги връша мястѿо където да се
# постави думата.
# 1. Проверява дали думата не се е появявала вече преди, като обхожда
# създадената стрꙋтура (масив)за същата дума. Как разбираме, че думата е
# същата? разбираме, като видим: 1) че е била написана по същия начин
# съкратена; 2) че е развързана по същия начин; 3)че регулярният ѝ израз е
# същия. Едно ѿ тези условия е достатъчно.
sub is_word_already_met ($self, $word = {}) {
  my $words             = $self->changed_words;
  my $already_met_index = @$words;                # after the end
  for my $i (0 .. $already_met_index - 1) {
    if ($word->{Променена} eq $words->[$i]{Променена}) {
      return $i;
    }
    if ($word->{Източник} eq $words->[$i]{Източник}) {
      return $i;
    }
    elsif ($word->{ИзразЗаТърсене} eq $words->[$i]{ИзразЗаТърсене}) {
      return $i;
    }
  }
  return $already_met_index;
}

# Добавя променената(разсъкратена/развързана) дума към стрꙋтурата, ѿ която ще
# направим речника.
# Как?
# 0. Използва is_word_already_added, за да види дали думата вече не е
# добавена при нягое предишно пускане  и ако е така, не прави нищо.
# 1. Използва is_word_already_met, да провери, дали думата не е срещана вече.
# ако се появява, просто я добавя след първѿо появяване и добавя ключ към
# описанието на думата първи ред на страница (first_page_line (occurence)).а
# 2. Ако не се появява, просто я добавя към края на масива.
# Връща true при добавяне или false иначе.
sub add_changed_word ($self, $word = {}) {

  # ще проверим първо дали думата вече не съществува и ще видим какво
  # ще правим.
  return 0 if $self->is_word_already_added($word);
  my $words = $self->changed_words;
  my $index = $self->is_word_already_met($word);
  my $at    = $index;
  if ($index < @$words) {
    $word->{ПървоНамеренаНаРед} = $words->[$index]{РедВРъкописа};
    $at = $index + 1;
  }
  splice @$words, $at, 0, $word;
  return 1;
}

# Extracts changed words from the passed line and adds them to an array of
# structures describing the words
sub extract_changed ($self, $line, $page, $pg_line, $source, $changed) {
  my @source  = split /\W+/, $source;
  my @changed = split /\W+/, $changed;
  if (@source < @changed) {

    # може би имаме възвратен глагол?
    $self->log([\@source, \@changed]);

    # да проверим за  словоформа с надписано "с" или ж - сѧ,съ,же
    # Развързана словоформата се сътои от две единици
    # Примери:Врѣмениⷤ҇  => Врѣмени же; лишитиⷭ҇ => лишити сѧ; днⷭ҇е => дьне съ
    for my $i (0 .. @source - 1) {
      my $next_i = $i + 1;
      if ($source[$i] =~ /\x{2ded}|\x{2de4}/
        && ($changed[$next_i] // '') =~ /^(?:с[ъьѧꙙ]|же)$/i)
      {
        $self->log("!!!$source[$i]|$changed[$i] $changed[$next_i]");

        # махаме възвратаната частица, за да изравним масивите, след като върнем
        # частицата в предния елемент.
        $changed[$i] = $changed[$i] . ' ' . $changed[$next_i];

        #splice ARRAY,   OFFSET,  LENGTH
        splice @changed, $next_i, 1;
        $self->log([\@source, \@changed]);
      }
      if ($source[$i] ne $changed[$i]) {
        $self->log("$source[$i]|$changed[$i]");
        $self->add_changed_word({

          # как ще търсим леѯемата в други документи
          'ИзразЗаТърсене' => $self->make_word_regex($changed[$i]),
          'Източник'       => $source[$i],
          'Променена'      => $changed[$i],
          'РедВРъкописа'   => $line,
          'РедВСтраницата' => $pg_line,
          'Редът'          => $source,
          'Страница'       => $page,
        });
      }
    }
  }

  # !Missing word in the changed line? Die so the editor can examine the situation.
  elsif (@source > @changed) {
    warn qq|
!!! Probably a missing word! Please see what you did at line $line.
        @source
        @changed
|;
  }

  #различават се само думите
  else {
    for my $i (0 .. @source - 1) {
      if ($source[$i] ne $changed[$i]) {
        $self->log("$source[$i]|$changed[$i]");
        $self->add_changed_word({

          # как ще търсим леѯемата в други документи
          'ИзразЗаТърсене' => $self->make_word_regex($changed[$i]),
          'Източник'       => $source[$i],
          'Променена'      => $changed[$i],
          'РедВРъкописа'   => $line,
          'РедВСтраницата' => $pg_line,
          'Редът'          => $source,
          'Страница'       => $page,
        });
      }
    }
  }
}

# extracts word_lines which are not abbreviated in the cleaned file but are
# abbreviated in the source file and searches for similar not abbreviated word_lines
# in each $self->files starting from the souse file.
# returns $self;
sub compare_word_lines($self) {

  #get all word_lines from from the cleaned and disabreviated file
  my $changed = $self->word_lines;
  my $source  = $self->source_file_lines;
  my $r       = $self->range;
  my $stop    = $r->[1] > @$source ? @$source - 1 : $r->[1];
  my $line    = 0;
  warn "Stop index for range is bigger than the last line!"
    . "\nChanging it to last line "
    . ($stop + 1)
    if $r->[1] > @$source;
  my ($page, $pg_line) = ('', 1);

  for my $wi (0 .. $stop) {

    # броене на редове и намиране на страници
    $line = $wi + 1;
    if ($source->[$wi] =~ /\d+[vr]/) {
      $page    = $source->[$wi];
      $pg_line = 1;
    }
    next if $wi < $r->[0];

    #find changed words, extract them and search in the whole file
    if ($self->diff($source->[$wi], $changed->[$wi])) {
      $self->log(<<"QQ");
$line:
    $source->[$wi]
    $changed->[$wi]
QQ

      $self->extract_changed($line, $page, $pg_line, $source->[$wi], $changed->[$wi]);
    }
    $pg_line++;
  }

  $self->changed_words_file->spurt(YAML::XS::Dump($self->changed_words));
}

has index_file   => sub { path($_[0]->data_dir, 'index.yml') };
has subprocs_num => 4;
has words_per_subproc =>
  sub($me) { int scalar(keys %{$me->unique_changed_words}) / $me->subprocs_num + 1 };

sub search_words_in_docs_in_subprocess ($self, $proc_num, $words = []) {
  my $subproc = Mojo::IOLoop::Subprocess->new;

  return $subproc->run_p(sub {
    my $index = {};
    for my $w (@$words) {

     # my $key = sprintf('%03d', $w->{РедВРъкописа}) . "|$w->{Източник}=>$w->{Променена}";
      my $key = lc $w->{Променена};

      # документите по близост
      my $closeness = $self->closeness;
      $self->log(
        "($proc_num) Търсене на $w->{Източник}:$w->{Променена}:$w->{ИзразЗаТърсене}…");
      $index->{$key} = $w;
      $self->files_contents->each(
        sub ($text, $n) {

          #say $text;
          my ($title) = $text =~ /Текстов корпус\n([^\n]+?)\n/s;
          my ($doc)   = $text =~ /doc_id(doc_\d{3})/s;

          # не само цели думи:
          # /((?:\w+\W+){0,3}(?:\w+)?$w->{ИзразЗаТърсене}(?:\w+)?+(?:\s+\w+){0,3})/gs
          # Само цели думи
          # /((?:\w+\W+){0,3}$w->{ИзразЗаТърсене}(?:\s+\w+){0,3})/gs
          my $matches
            = [$text =~ /((?:\w+\W+){1,3}$w->{ИзразЗаТърсене}(?:\W+\w+){1,4})/gs
            ];

          #say dumper $matches;
          if (@$matches) {

            # По-късите съвпадения - първи.
            @$matches = sort { length($a) <=> length($b) } @$matches;

            # Най-близко(!) разночетене според близостта на документа до
            # променяния ръкопис. Това е целта на цялѿо индеѯиране - да
            # помогне за вземането на рещенѥ коя е най-добрата словоформа
            # за развързване на съкращенѥто.
            my $razni = c(@{$index->{$key}{Разночетения} //= []});

            # да бъдат само на един ред
            for my $i (0 .. @$matches - 1) { $matches->[$i] =~ s/\s+/ /gs; }

            # Ще показваме до 12 намирания на документ
            splice @$matches, 11, (@$matches - 12) if @$matches > 12;

            # Разночетения!
            my $how_close = sprintf("%02d|$doc", $closeness->{$doc});
            for my $raz (@$matches) {
              my @nameri = $raz =~ /($w->{ИзразЗаТърсене})/g;
              for my $namera (@nameri) {
                my $first
                  = $razni->first(sub ($e) { $e && exists $e->{"$how_close|$namera"} });
                if ($first) {
                  $first->{"$how_close|$namera"}++;
                  push @{$first->{Примери}}, $raz;
                }
                else {
                  push @$razni, {"$how_close|$namera" => 1, Примери => [$raz]};
                }
              }
            }
            $index->{$key}{Разночетения} = [@$razni];

            # $index->{$key}{Намерени}{$how_close} = $matches;
          }
        });    # end $self->files_contents->each(sub{...})

    }
    path($self->data_dir, sprintf('index_%02d' . '.yml', $proc_num))
      ->spurt(YAML::XS::Dump($index));
    my $msg
      = "($proc_num) searched for "
      . @$words
      . " words from $words->[0]{Променена} to $words->[-1]{Променена} !";
    $self->log($msg);
    return $msg;
  })->then(sub { })->catch(sub  ($err) {
    $self->log("Subprocess ($proc_num) error: $err");
  });
}

sub search_in_docs ($self) {
  my $words    = $self->unique_changed_words;
  my $wordkeys = [sort keys %$words];

  #say $self->files_contents->size;
  my @subprocs;
  my $chunk_size = $self->words_per_subproc;
  my $proc_num   = 1;
  while (@$wordkeys) {
    my @chunk_of_wordkeys = splice @$wordkeys, 0, $chunk_size;
    push @subprocs,
      $self->search_words_in_docs_in_subprocess($proc_num++,
      [@$words{@chunk_of_wordkeys}]);
  }

  foreach my $s (@subprocs) {

    # Start event loop if necessary
    $s->ioloop->start unless $s->ioloop->is_running;
  }

  foreach my $s (@subprocs) {

    # Wait for the subprocess to finish
    $s->wait;
  }

  # merge index files into one
  my $index = {};
  for (1 .. $self->subprocs_num) {
    $index = {
      %$index,
      %{
        YAML::XS::Load(path($self->data_dir, sprintf('index_%02d' . '.yml', $_))->slurp)}
    };
  }

  path($self->data_dir, 'index.yml')->spurt(YAML::XS::Dump($index));
  return;
}

sub sudgest_changes($self) {
  die "TODO";
}

sub main() {
  my $wf = __PACKAGE__->new;
  getopt

    #'W|word_lines=s@' => sub ($name, $value) {$wf->word_lines($value);},
    'R|range=s@' => sub ($name, $value) {
    state $call = 0;
    if ($call > 1) {
      warn( "The range can contain only two items - start index and stop index"
          . "\nNot adding value $value!");
      return;
    }
    $wf->range->[$call] = $value;
    $call++;
    }, 'F|files=s@' => sub ($name, $value) { $wf->files($value) },
    'D|debug' => sub ($n, $v) {
    $wf->debug($v);
    },
    'S|subprocesses=i' => sub ($n, $v) {
    $v = $v > 10 ? 10 : $v;
    $wf->subprocs_num($v);
    };

  $wf->compare_word_lines();
  say "Общо променени думи:" . (@{$wf->changed_words});
  say "неповтарящи се променени думи:" . (keys %{$wf->unique_changed_words});

  #now search each unabbreviated word in each doc_ file
  $wf->search_in_docs();

  # Сега можем да предложим промяна на развързаната дума, ако се различава от
  # най-близко намерената.
  $wf->sudgest_changes();
}


main() if not caller();
1;
