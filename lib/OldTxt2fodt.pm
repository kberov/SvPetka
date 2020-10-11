#!/usr/bin/env perl
package OldTxt2fodt;

#use open ':encoding(UTF-8)';
use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);

use FindBin qw($RealBin);
use Mojo::DOM;
use YAML::XS;
use Mojo::Collection qw(c);
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);
binmode STDOUT => ':utf8';
binmode STDERR => ':utf8';
no warnings 'redefine';
local *Data::Dumper::qquote  = sub {qq["${\(shift)}"]};
local $Data::Dumper::Useperl = 1;


# Ѿваря и чете файла, съдържащ стария теѯт, пригѿвен на целини за внасяне в
# изследването, ѿляво на превода. Връща теѯта като Mojo::Collection ѿ целини
has old_text_to_import => sub {
  my $f = path($RealBin, '../texts/Prostranno-Evt-ZogrSb-chist-para.txt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  return c(split(/\n/, decode(utf8 => $f->slurp)));
};

# .fodt файлът като Mojo::File обект
has diploma_work_file => sub {
  my $f = path($RealBin, '../wip/EvtimijPetkaZograf074.fodt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  return $f;
};

# Ѿваря и чете XML файла в който ще внесем стария теѯт на параграфи.
has fodt_dom => sub { Mojo::DOM->new(decode(utf8 => $_[0]->diploma_work_file->slurp)); };

#  Връща
# съдържанѥто на лѣвата колонка на таблицата като Mojo::Collection ѿ Mojo::DOM
# обекти на документа C<fodt_dom>.
has fodt_dom_left_column_cells => sub {
  my $left_column_cells_text
    = 'table|table[id="Vita"] table|table-row  table|table-cell:first-child > text|p';
  return $_[0]->fodt_dom->find(
    $left_column_cells_text,
    table  => 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    text   => 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    office => 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
  );
};

# Извършва проверки за броя на целините и каквито други е необходимо в стария и
# съвременния теѯт, за да се увери, че внасянето ще мине безпрепятствено. Убива
# програмата със съѿветнѿо събщение за проверката и вероятната промяна, която
# човек трѣбва да направи, преди да опита ѿново внасяне.
sub perform_checks ($self) {
  my $oti = $self->old_text_to_import;
  my $otx = $self->fodt_dom_left_column_cells;
  if ($oti->size != $otx->size) {
    warn <<"ERR";
        Размерът на стария теѯт: ${\$oti->size} 
        се различава ѿ 
        размера на стария теѯт:  ${\$otx->size} 
        в лявата колона на таблицата!
        Трябва да са равни!!!
        Следва показване на редовете един по един, за да сравните нагледно!
ERR
    sleep 2;
    $oti->each(
      sub ($e, $n) {
        say sprintf("T%03d:", $n) . $e;
        my $xe = $otx->[($n - 1)]->all_text;
        $xe =~ s/^\s+//;
        $xe =~ s/\s+$//;
        say sprintf("X%03d:", $n) . $xe;

        #say $xe->selector;
        say $/;
        sleep 1 if ($e ne $xe);
      });
  }
  return $self;
}

sub import_old_text($self) {

  my $oti = $self->old_text_to_import;
  my $otx = $self->fodt_dom_left_column_cells;
  $oti->each(
    sub ($e, $n) {

      # махаме начални и крайни празнѿи
      $e =~ s/^\s+//;
      $e =~ s/\s+$//;

      # махаме повече ѿ една празнѿа
      $e =~ s/\s+/ /g;

      # Да нѣма сираци, останали сами на ред
      $e =~ s/\s+(\S+)$/\x{00A0}$1/;
      my $xe     = $otx->[$n - 1];
      my $xe_txt = $xe->text;
      say sprintf("%03d:", $n) . "$/$e$/$xe_txt" if $e ne $xe_txt;
      if ($e =~ /\S+/) {
        $xe->content(qq|$e|);
      }
      else {
        $xe->content(qq||);
      }

      #      sleep 1;
    });

  $self->diploma_work_file->spurt(encode utf8 => $otx->first->root->to_string);
}

sub main() {
  my $oldt = OldTxt2fodt->new->perform_checks;

  #say $oldt->old_text_to_import->first;
  #say $oldt->old_text_left_column_cells->first->all_text;
  $oldt->import_old_text();
}

main() if not caller();

1;

