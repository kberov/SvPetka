#!/usr/bin/env perl
package Index2fodt;

use FindBin qw($RealBin);
use lib $RealBin;

#use open ':encoding(UTF-8)';
#Да използваме някои вече гѿови способности!
use Mojo::Base 'OldTxt2fodt', -signatures;

use Mojo::Collection qw(c);
use Mojo::File qw(path);
use Mojo::Template;
use Mojo::Util qw(decode encode getopt dumper);
use feature qw(lexical_subs unicode_strings);
no warnings 'redefine';
local *Data::Dumper::qquote  = sub {qq["${\(shift)}"]};
local $Data::Dumper::Useperl = 1;

# Винаги искаме свежи данни ѿ диска.
sub unique_changed_words_file_content ($self) {
  my $f = path($RealBin, '../data', 'index.yml');
  return {} unless -f $f && -s $f;
  return YAML::XS::LoadFile($f);
};

# Връща секцията на Индеѯа като ДОМ обект
has fodt_index_section => sub {

  return $_[0]->fodt_dom->at(
    'text|section[text|name="Указател"]' => (
      table  => 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
      text   => 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
      office => 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    ));
};

sub import_index($self) {
  my $mt = Mojo::Template->new(vars => 1)->parse(<<'WORD');
% my ($red_izt, $red_razg) = split /\n/, $w->{'4Редове'}[0];
% my($red_str) = $red_izt =~ /^(.+)\:/;
% $red_izt =~ s/^.+\://;
   <text:p text:style-name="WFOL"><%==
        $w->{'0Изт.|Разг.'} .' '.$red_str %><text:line-break/><%== $red_izt %>\
%#        </text:p>
%#   <text:p text:style-name="Regexp"><%== $w->{'1ЗаТърсене'} %></text:p>
%#   <text:p text:style-name="Съвпадение">\
% my $count = 0;
% if($w->{'Съвпадения'} && @{$w->{'Съвпадения'}}) {
<text:line-break/>\
%   MATCHES: for my $match (@{$w->{'Съвпадения'}}) {
%#= Mojo::Util::dumper $match;
%       my ($k,$v) = each %$match;
%       for my $line(@$v){
<%== $k .': '. ($line =~ s/\s+$//r)=%>
%       $count++;last MATCHES if $count == $show_matches;
%= '; '
%       }
%   }
% }
</text:p>
WORD
  my $words   = $self->unique_changed_words_file_content;
  my $content = '';
  my $c       = 0;
  my $letter  = 'Z';
  for my $w (sort { fc $a cmp fc $b} keys %$words) {

    # Сменихме на следващата буква
    unless ($w =~ /^$letter/) {
      ($letter) = $w =~ /^(\w)/;
      $content .= qq|<text:p text:style-name="IHeading2">${\uc($letter)}</text:p>$/|;
    }
    $content .= $mt->process({w => $words->{$w}, show_matches => 3});

    #sleep 3;
    # last if ++$c > 600;
  }
  my $doc = $self->fodt_index_section->content($content)->root;

#say $doc->all_text;
  $self->diploma_work_file->spurt(encode utf8 => $doc);
  return;
}

sub main() {
  my $oldt = __PACKAGE__->new->import_index();
}

main() if not caller();

1;
