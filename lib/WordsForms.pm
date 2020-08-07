#!/usr/bin/env perl
package WordsForms;

use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);

use FindBin qw($RealBin);
use IO::Dir;
use Mojo::DOM;
use Mojo::JSON 'encode_json';
use Mojo::Collection 'c';
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);
binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';
no warnings 'redefine';
local *Data::Dumper::qquote  = sub {qq["${\(shift)}"]};
local $Data::Dumper::Useperl = 1;


has distances => sub {
  c(
    'doc_155', 'doc_156', 'doc_214', 'doc_212', 'doc_216', 'doc_217', 'doc_219',
    'doc_220', 'doc_221', 'doc_222', 'doc_223', 'doc_225', 'doc_157', 'doc_213',
    'doc_158', 'doc_159', 'doc_197', 'doc_202', 'doc_205', 'doc_211',

  );
};

# бꙋкви за създаване на израз ѿ примерна дума и търсене
has bukvi => sub {
  my $l = {
    'о'  => "[оѡꙫѻꙩ]",
    'ѡ'  => "[оѡꙫѻꙩ]",
    'ꙫ'  => "[оѡꙫѻꙩ]",
    'ѻ'  => "[оѡꙫѻꙩ]",
    'ꙩ'  => "[оѡꙫѻꙩ]",
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
    'ꙋ'  => '[ꙋѹу]',
    'ѹ'  => '[ѹꙋу]',
    'у'  => '[уꙋѹ]',
    'ѫ'  => '[ѫуꙋ]',
    'їе' => '(?:їе|ѥ|іе)',
  };
  my @glasni = keys %$l;
  $l = {'з' => "[зѕꙁꙃ]", 'ѕ' => "[ѕзꙁꙃ]", 'ꙁ' => "[ꙁзѕꙃ]", 'ꙃ' => "[ꙃзѕꙁ]", %$l};

  my @syglasni = (qw(б в г д ж к л м н п р с т ф х ц ч ш щ з ѕ ꙁ ꙃ ѿ));
  for my $b (@syglasni) {
    for my $y (@glasni) {
      $l->{"$b$y"} = "$b$l->{$y}";
      $l->{$b} = "$b$l->{ъ}";
    }
    $l->{'н'} = "[eьъꙿ]?н$l->{ъ}";

  }
  return $l;
};

sub make_word_regex ($self, $w) {
  state $l = $self->bukvi;

  # longer keys first
  state $rex_keys = [sort { length($b) <=> length($a) } sort keys %$l];

  # build the regex for this word
  state $rex_keys_rex = join '|', @$rex_keys;

  #say $rex_keys_rex;
  my $m   = '';
  my $rex = $w =~ s/($rex_keys_rex)/
        (($m = lc $1) && ($l->{$m} ? $l->{$m} : $m))
        /xiger;
  $rex = qr/$rex/iu;
  say "$w:/$rex/";
  return $rex;
}

# Думи, които взимаме ѿ файла, който ще проверяваме, ако не са подадени на
# реда.
sub words ($self, $wfs = []) {
  if (scalar @$wfs) {

    # words are passed from the commandline
    for (0 .. @$wfs - 1) {
      $wfs->[$_] = decode utf8 => $wfs->[$_];
    }

    $self->{words} = $wfs;

    return $self;
  }
  if (!$self->{words}) {
    my $file = path("$RealBin/../texts/Prostranno-Evt-ZogrSb-chist.txt")->realpath;
    say STDERR "No word forms passed on the command line via -W"
      . " Using default file "
      . $file;
    -f $file && -s $file || die "The file $file is not a file or it is empty";
    $wfs = [split '\W+', decode(utf8 => $file->slurp)];
    $self->{words} = $wfs;
    return $self;
  }

  # already called once and assigned
  return $self->{words} if $self->{words};

};

# files to search for words
sub files ($s, $files = []) {
  return $s->{files} if !@$files && $s->{files};
  $s->{files} = [
    map {
      die "File $_ is empty or not a file!" unless -f $_ && -s $_;
      my $f = path($_)->realpath;
    } @$files
    ]
    if @$files;

  return $s if @$files;

  #reading default files
  my $from_dir = "$RealBin/histdict_evt_docs";
  my $dir = IO::Dir->new($from_dir) or die($!);
  my @files;
  while (defined($_ = $dir->read())) {
    push(@files, path $from_dir, $_);
  }
  $s->{files} = [sort(@files)];
  return $s;
}
has source_file => sub {path("$RealBin/../texts/Petka_NOVA_chist.txt")->realpath;};

sub main() {
  my $wf = __PACKAGE__->new;
  getopt 'W|words=s@' => sub ($name, $value) {
    $wf->words($value);
  }, 'F|files=s@' => sub ($name, $value) { $wf->files($value) };
  say dumper $wf->words->words;

  #$wf->make_word_regex($_) for @{(ref $wf->words eq 'ARRAY') || $wf->words};
}


main() if not caller();
1;
