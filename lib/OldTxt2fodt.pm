#!/usr/bin/env perl
package OldTxt2fodt;
#use open ':encoding(UTF-8)';
use Mojo::Base -base, -signatures;
use feature qw(lexical_subs unicode_strings);

use FindBin qw($RealBin);
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(decode encode getopt dumper);
binmode STDOUT => ':utf8';
