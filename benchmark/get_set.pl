#!/usr/bin/env perl

use strict;
use warnings;

use P5opaque;

use Benchmark qw[ cmpthese ];

{
    package PP::P5opaque::slots;
    use strict;
    use warnings;

    sub get { $_[0]->{ $_[1] } }
    sub set { $_[0]->{ $_[1] } = $_[2] }
}

my $o = P5opaque::newMopIV();
my $x = {};

P5opaque::slots::set($o, 'test', 0);
PP::P5opaque::slots::set($x, 'test', 0);

cmpthese(
    1_000_000 => {
        'XS' => sub { P5opaque::slots::set($o, 'test', P5opaque::slots::get($o, 'test') + 1) },
        'PP' => sub { PP::P5opaque::slots::set($x, 'test', PP::P5opaque::slots::get($x, 'test') + 1) },
    }
);

1;