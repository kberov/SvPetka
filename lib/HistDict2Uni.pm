#!/usr/bin/env perl
package HistDict2Uni;

#use open ':encoding(UTF-8)';
use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);

use FindBin qw($RealBin);
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);
binmode STDOUT => ':utf8';

my sub prepare_find_repl_hash() {

  # the order of this "find and replace" matters
  my @find_repl = (
    "" => "ѥ҃",
    ""  => "ѥ",
    "" => "и҃",
    ""  => "и",
    "" => "ч҃",
    ""  => "ч",
    "ћ" => "ћ҃",

    #  => 🞣
    # U+E30D <Лична употреба>(кръст) се замества с
    # U+1F7A3 MEDIUM GREEK CROSS
    "\x{e30d}" => "\x{1f7a3}",

    # U+E033 <Лична употреба> пеперудка,
    # използвано като покритие се замества с
    # U+0487 COMBINING CYRILLIC POKRYTIE
    "\x{e033}" => "\x{0487}",

    # U+E02D <Лична употреба> стрелка наляво
    # се замества с
    # U+0487 COMBINING CYRILLIC POKRYTIE
    # или трябва д асе замести всъщност с U+0484 COMBINING CYRILLIC PALATALIZATION
    "\x{e02d}" => "\x{0487}",

    #U+0360 COMBINING DOUBLE TILDE
    # се замества с
    # U+0483 COMBINING CYRILLIC TITLO
    "\x{0360}" => "\x{0483}",

    # U+E213 <Лична употреба> и U+E212 <Лична употреба> се заместват с указанѿо
    # за целта в уникод таблицата U+A669 CYRILLIC SMALL LETTER MONOCULAR O и
    # U+A668 CYRILLIC CAPITAL LETTER MONOCULAR O
    "\x{e213}" => "\x{a669}",
    "\x{e212}" => "\x{a668}",

    # U+E20C <Лична употреба> заместваме с главно Ч
    # U+0427 CYRILLIC CAPITAL LETTER CHE
    "\x{e20c}" => "\x{0427}",

    #  => ѳ
    "\x{e225}" => "\x{0473}",
    "\x{e224}" => "\x{0472}",

    #  => e
    # U+E21F <Лична употреба> се замества с U+0435 CYRILLIC SMALL LETTER IE
    "\x{e21f}" => "\x{0435}",
    q|еⷩ|     => "еⷩ҄",
    "д"       => "Д꙯",
    "пⷭ"      => "пⷭ҄",
    "а"       => "a꙽",
    "ѩ"       => "ѩ҃",
  );


  my $find_repl = {
    " ⷭ" => " ҄ⷭ",
    " ⷮ" => " ҄ⷮ",
    "ⷭ"  => " ҇",
    ""   => "ꙙ",
    "ї"  => "ї҃",
    "ꙇ"  => "ꙇ҃",
    "а"  => "а҃",
    "б"  => "б҃",
    "в"  => "в҃",
    "г"  => "г҃",
    "д"  => "д҃",
    "е"  => "е҃",
    "ж"  => "ж҃",
    "з"  => "з҃",
    "и"  => "и҃",
    "й"  => "й҃",
    "к"  => "к҃",
    "л"  => "л҃",
    "м"  => "м҃",
    "н"  => "н҃",
    "о"  => "о҃",
    "п"  => "п҃",
    "р"  => "р҃",
    "с"  => "с҃",
    "т"  => "т҃",
    "у"  => "у҃",
    "ф"  => "ф҃",
    "х"  => "х҃",
    "ц"  => "ц҃",
    "ч"  => "ч҃",
    "ш"  => "ш҃",
    "щ"  => "щ҃",
    "ъ"  => "ъ҃",
    "ы"  => "ы҃",
    "ь"  => "ь҃",
  };
  my @first_keys;
  for my $i (0 .. @find_repl - 1) {
    push(@first_keys, $find_repl[$i]) if $i % 2 == 0;
  }
  my $key_str = join("|", @first_keys, keys %$find_repl);

  #merge @find_repl with %$find_repl
  $find_repl = {@find_repl, %$find_repl};
  return {regex => $key_str, find_repl_hash => $find_repl};
}

has file_path => '';

has file_contents => sub {
  decode(utf8 => path($_[0]->file_path)->slurp);
};
$|++;

# Replaces odd characters in utf8 decoded texts from histdict.
sub replace ($self) {
  my $text = $self->file_contents;

  #this is a html file which needs to be cleaned
  if ($text =~ /<body/) {

    #add some new lines: <br>, <p>
    $text =~ s/(<br\/>)/$1\n/g;

    # remove multiple new lines
    $text =~ s/\t+//gs;
    my $dom = Mojo::DOM->new($text);

    # remove menu
    if (my $m  = $dom->at("#menu"))         { $m->remove }
    if (my $co = $dom->at('content_title')) { $co->remove }
    $text = $dom->at('body')->all_text;    # =~ s/\s+/ /sgr;
    $text =~ s/[\r\n]+/\n/gs;
  }

  # replace all broken symbols (Those from the private unicode space) with the
  # correct ones
  state $f_r = prepare_find_repl_hash;

  # say $f_r->{regex};
  $text =~ s/($f_r->{regex})/$f_r->{find_repl_hash}{$1}/ge;
  return $text;
}

# За да се оправят всички файлове в папка
# да направя следнѿо на командния ред:
#  cd histdict_evt_docs/
#  rm *_clean
# for f in $(ls ./); do ../lib/HistDict2Uni.pm -F $f> ${f}_clean; done

sub main() {
  getopt 'F|file=s' => \my $path;

  $path || do {
    say "Please pass a file to clean:\n $0 -F path/to/filename.txt";
    exit;
  };
  -f $path || do {
    say "$path is not a file. ";
    exit;
  };
  my $uni = HistDict2Uni->new(file_path => $path);

  #my ($start,$stop) = (910,100);
  #say substr($uni->file_contents, $start, $stop);

  my $text = $uni->replace();

  #say '-----------------';

  #say dumper substr($text, 450, 400);
  say $text;

  #say substr($text, $start, $stop);
  #say dumper substr("гл͠", 0, 400);
}

main() if not caller();

1;
