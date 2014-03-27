#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Data::Dumper qw[ Dumper ];

BEGIN {
    use_ok('P5opaque')
};

{
    my $o = \(my $x);
    P5opaque::initialize_instance($o);

    ok($o, '... need a test in here');

    ok(!P5opaque::has_events($o), '... no events yet');

    my $test       = 0;
    my $test_event = sub { $test++ };

    P5opaque::bind($o, 'test', $test_event);

    ok(P5opaque::has_events($o), '... have events now');
    is($test, 0, '... test event has not been fired');

    P5opaque::fire($o, 'test');

    is($test, 1, '... test event has been fired');

    P5opaque::unbind($o, 'test', $test_event);

    ok(!P5opaque::has_events($o), '... no events anymore');

    P5opaque::fire($o, 'test');
    is($test, 1, '... test event was not fired again');

}

{
    my $o = \(my $x);
    P5opaque::initialize_instance($o);

    ok(!P5opaque::has_events($o), '... no events yet');

    my @tests;
    my @events;
    foreach my $i (0 .. 10) {
        $tests[$i]  = 0;
        $events[$i] = sub { $tests[$i]++ };

        P5opaque::bind($o, 'test', $events[$i]);
    }

    ok(P5opaque::has_events($o), '... have events now');
    is($tests[$_], 0, '... test ('.$_.') event has not been fired')
        foreach 0 .. 10;

    P5opaque::fire($o, 'test');
    P5opaque::fire($o, 'test');
    P5opaque::fire($o, 'test');

    is($tests[$_], 3, '... test ('.$_.') event has not been fired')
        foreach 0 .. 10;
}

done_testing;

