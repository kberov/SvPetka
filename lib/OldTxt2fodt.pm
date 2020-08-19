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
    my $f = path($RealBin,'../texts/Prostranno-Evt-ZogrSb-chist-para.txt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  return c(split(/\n/, decode(utf8 => $f->slurp)));
};

# .fodt файлът като Mojo::File обект
has diploma_work_file => sub {
    my $f = path($RealBin,'../wip/EvtimijPetkaZograf074.fodt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  return $f;
};

# Ѿваря и чете XML файла в който ще внесен стария теѯт на параграфи.  Връща
# съдържанѥто на лѣвата колонка на таблицата като Mojo::Collection ѿ Mojo::DOM
# обекти на документа.
has old_text_left_column_cells => sub {
  my $left_column_cells_text = 'table|table-cell[table|style-name="Житието.A1"]>text|p"]';
  return Mojo::DOM->new(decode( utf8=>$_[0]->diploma_work_file->slurp))
  ->find($left_column_cells_text, table => 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',text=> 'urn:oasis:names:tc:opendocument:xmlns:text:1.0');
};

# Извършва проверки за броя на целините и каквито други е необходимо в стария и
# съвременния теѯт, за да се увери, че внасянето ще мине безпрепятствено. Убива
# програмата със съѿветнѿо събщение за проверката и вероятната промяна, която
# човек трѣбва да направи, преди да опита ѿново внасяне.
sub perform_checks ($self){
    my $oti = $self->old_text_to_import;
    my $otx = $self->old_text_left_column_cells;
    if($oti->size != $otx->size){
        warn <<"Т";
        Размерът на стария теѯт: ${\$oti->size} 
        се различава ѿ 
        размера на стария теѯт:  ${\$otx->size} 
        в лявата колона на таблицата!
        Трябва да са равни!!!
        Следва показване на редовете един по един, за да сравните нагледно!
Т
sleep 2;
       $oti->each(sub($e,$n){
            say sptintf("T%03d:",$n).$e;
            my $xe = $otx->[$n-1]->all_text;
            $xe =~ s/^\s+//;
            $xe =~ s/\s+$//;
            say sptintf("X%03d:",$n).$xe;
            sleep 1 if($e ne $xe);
           })
    }
    return $self;
}

sub main() {
my $oldt = OldTxt2fodt->new->perform_checks;
say  $oldt->old_text_to_import->first;
say $oldt->old_text_left_column_cells->first->all_text;
}

main() if not caller();

1;

