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
no warnings 'redefine';
local *Data::Dumper::qquote  = sub {qq["${\(shift)}"]};
local $Data::Dumper::Useperl = 1;



has distances => sub{
c(
'doc_155',
'doc_156',
'doc_214',
'doc_212',
'doc_216',
'doc_217',
'doc_219',
'doc_220',
'doc_221',
'doc_222',
'doc_223',
'doc_225',
'doc_157',
'doc_213',
'doc_158',
'doc_159',
'doc_197',
'doc_202',
'doc_205',
'doc_211',

);
};
# бꙋкви за създаване на израз ѿ примерна дума и търсене
has bukvi => sub{
    {
        'о' =>"[оѡꙫѻꙩ]",
        'ѡ' =>"[оѡꙫѻꙩ]",
        'ꙫ' =>"[оѡꙫѻꙩ]",
        'ѻ' =>"[оѡꙫѻꙩ]",
        'ꙩ' =>"[оѡꙫѻꙩ]",
        'з' =>"[зѕꙁꙃ]",
        'ѕ' =>"[зѕꙁꙃ]",
        'ꙁ' =>"[зѕꙁꙃ]",
        'ꙁ' =>"[зѕꙁꙁ]",
        'ы' =>"[ыꙑ]",
        'ыи' =>"[ыꙑ]и?",
        'ꙑ' =>"[ыꙑ]",
        'ꙑи' =>"[ыꙑ]и?",
        'ъ' =>"[ьъ]?",
        'ь' =>"[ьъꙿ]?",
        'ꙿ' =>"[ьъꙿ]?",
        'е' =>"[єеѧꙙ]",
        'є' =>"[еєѧꙙ]",
        'ѧ' =>"[ѧꙙеє]",
        'ꙙ' =>"[ꙙѧеє]",
        'и' =>"[ийії]",
        'й' =>"[йиії]",
        'і' =>"[іїий]",
        'ї' =>"[їіий]",
        'ꙗ' =>"(?:ꙗ|їа|іа|иа)",
        'їа' =>"(?:ꙗ|їа|іа|иа)",
        'іа' =>"(?:ꙗ|їа|іа|иа)",
        'иа' =>"(?:ꙗ|їа|іа|иа)",
        'ꙋ' => '[ꙋѹу]',
        'ѹ' => '[ѹꙋу]',
        'у' => '[уꙋѹ]',
        'їе' =>'(?:їе|ѥ|іе)'
    }
};

sub make_word_regex ($self,$w){
    state $l = $self->bukvi;
    # longer keys first
    my $rex_keys =  [sort {length($b)<=>length($a)} keys %$l];
    # build the regex for this word
   my $rex_keys_rex = join '|', @$rex_keys;  
    my $rex = $w =~ s/($rex_keys_rex)/$l->{$1}?$l->{$1}:$1/ger;
    $rex = qr/$rex/iu;
    say "$w:$rex";
    return $rex;
}
sub main() {
    my $word_forms = [];
    getopt 'W|words=s@' => \$word_forms;
   for my $i(0 .. @$word_forms-1){
    $word_forms->[$i] = decode utf8 => $word_forms->[$i];
   } 

   @$word_forms  || do {
        say "Please pass at least one word to search for";
        exit;
    };
    my $wf = __PACKAGE__->new;
    $wf->make_word_regex($_) for @$word_forms;
}



main() if not caller();
1;
