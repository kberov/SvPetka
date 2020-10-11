#!/usr/bin/env perl
package Txt2Html;
use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);
use open qw(:std :utf8);
use FindBin qw($RealBin);
use Mojo::DOM;
use YAML::XS;
use Mojo::Collection qw(c);
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);

# Ѿваря и чете файла, съдържащ стария теѯт, пригѿвен на целини за внасяне в
# изследването, ѿляво на превода. Връща теѯта като Mojo::Collection ѿ целини
has old_text => sub {
  my $f = path($RealBin, '../texts/Prostranno-Evt-ZogrSb-chist-para.txt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  my $txt = decode(utf8 => $f->slurp);

  # $txt =~ s/ꙋ/у/g;
  $txt =~ s/ꙁ/з/g;

  return c(split(/\n/, $txt));
};

# Ѿваря и чете файла, съдържащ новия теѯт, пригѿвен на целини за внасяне в
# изследването, ѿдѣсно на стария теѯт. Прилага някои автоматични промени в теѯта.
# Връща теѯта като Mojo::Collection ѿ целини.
has new_text => sub {
  my $f = path($RealBin, '../texts/Prostranno-Evt-SBL-T4str191-chist-para.txt')->realpath;
  die "$f:$!" unless -f $f && -s $f;
  my $txt = decode(utf8 => $f->slurp);
  return c(split(/\n/, $txt));
};
has endnotes_html => '';

# Finds a number in the passed line then finds the corresponding endnote and converts it to a h2 with the corresponding ID with the rest of the text
sub nums2sup_links($self) {
  my $belezki_reached = 0;
  my $note_qr         = qr/^(\d{1,2})(\.)\s+(.+)$/;
  my $endnotes_html   = '';
  my $new_text        = $self->new_text->each(sub {
    if (!$belezki_reached && $_ =~ /^БЕЛЕЖКИ/i) {
      $belezki_reached = 1;
    }
    if (!$belezki_reached && $_ =~ /\w+/) {
      $_ =~ s|(\D)(\d{1,2})|$1<sup><a name="txt_$2" href="#note_$2">$2</a></sup>|xg;
      $_ = qq|<p class="new_txt">$_</p>|;
    }
    if ($belezki_reached && $_ =~ $note_qr) {
      $_
        =~ s|$note_qr|<h2 id="note_$1"><a href="#txt_$1">$1$2</a></h2><p class="note">$3</p>|xg;
      $endnotes_html .= $_;
    }
  });
  $self->endnotes_html($endnotes_html);
  return $new_text;
}


sub make_html ($self) {
  my $new_txt = $self->nums2sup_links();
  my $table   = qq|<table id="text">\n|;

  $self->old_text->each(
    sub ($e, $num) {
      my $i = $num - 1;
      if ($e) {
        $table .= qq|<tr><td><p class="old_txt">$e</p></td>\n|
          . qq|<td>$i</td><td><p class="new_text">$new_txt->[$i]</p></td></tr>|;
      }
      else {
        $table .= qq|<tr class="empty"><td></td><td></td></tr>|;
      }
    });
  $table .= qq|\n</table>|;
  my $title   = substr($self->old_text->[0], 0, 20);
  my $content = <<"HTML";
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$title…</title>
    <style>
    .old_txt {
        font: 10pt Veleka, serif;
    }
    .note, .new_txt {
        font: 10pt "Acari Sans", sans-serif;
    }
     </style>
  </head>
  <body>
  <h1>$title</h1>
  $table
  <h1>БЕЛЕЖКИ</h1>
  ${\ $self->endnotes_html}
  </body>
HTML

  path($RealBin, '../data', 'parallel_text.html')->spurt(encode(utf8 => $content));
  return;
}

sub nothing {
  say 'Нѣма кво да праа. Чао!';
}

sub make_fodt ($self) {
  my $table = qq||;
  my $old_t = $self->old_text;
  my $new_t = $self->new_text->head($old_t->size);
  my $n     = 0;
  $old_t->each(
    sub ($e, $num) {
      my $i = $num - 1;
      if ($e) {
        $n++;

        # махаме начални и крайни празнѿи
        $e =~ s/^\s+//;
        $e =~ s/\s+$//;

        # махаме повече ѿ една празнѿа
        $e =~ s/\s+/ /g;

        # числѿо за бележка в края да изглежда повдигнато и по-малко
        # <text:span text:style-name="T69">1</text:span>
        $new_t->[$i]
          =~ s|(\D)(\d{1,2})|$1<text:span text:style-name="T69">$2</text:span>|xg;

        # Да нѣма сираци, останали сами на ред
        $e =~ s/\s+(\S+)$/\x{00A0}$1/;
        $table .= <<"A1";
          <table:table-row table:style-name="Vitae.2">
            <table:table-cell office:value-type="string" table:style-name="Vitae.A2">
              <text:p text:style-name="Източник">$n. $e</text:p>
            </table:table-cell>
            <table:table-cell office:value-type="string" table:style-name="Vitae.B2">
              <text:p text:style-name="Превод">$n. $new_t->[$i]</text:p>
            </table:table-cell>
          </table:table-row>
A1
      }
    });
  say $table;
}


sub main() {
  my $action = 'nothing';
  my $table  = __PACKAGE__->new;
  getopt 'A|do=s' => sub ($name, $value) {
    ($action) = $value =~ /(nothing|make_html|make_fodt)/;
    $action or die "!Нѣмоа таква неща да праа!";
    },
    ;

  $table->$action();

  #$new_txt->tail(5)->each(sub {say});
}

main() if not caller();

1;
