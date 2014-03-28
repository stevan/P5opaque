#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Data::Dumper qw[ Dumper ];
use Devel::Peek;

BEGIN {
    use_ok('P5opaque')
};

{
    my $o = \(my $x);
    P5opaque::newOVrv($o);

    ok($o, '... need a test in here');

    ok(!P5opaque::slots::has($o, "foo"), '... no value at slot "foo"');

    #P5opaque::slots::set($o, "foo", 10);
    #ok(P5opaque::slots::has($o, "foo"), '... have a value at slot "foo" now');

    #is(P5opaque::slots::get($o, "foo"), 10, '... got the correct value for slot "foo"');

    ok(!P5opaque::events::has_events($o), '... no events yet');

    warn("?? PERL");
    P5opaque::slots::set($o, "test", 0);
    warn("?? PERL");
    ok(P5opaque::slots::has($o, "test"), '... have a value at slot "test" now');

    my $test_event = sub {
        my $o = shift;
        my $x = P5opaque::slots::get($o, "test");
        warn(">> PERL");
        Dump($x);
        warn("<< PERL");
        P5opaque::slots::set($o, "test", $x + 1);
        return;
    };

    P5opaque::events::bind($o, 'test', $test_event);

    ok(P5opaque::events::has_events($o), '... have events now');
    is(P5opaque::slots::get($o, "test"), 0, '... test event has not been fired');

    P5opaque::events::fire($o, 'test');

    is(P5opaque::slots::get($o, "test"), 1, '... test event has been fired');

    P5opaque::events::unbind($o, 'test', $test_event);

    ok(!P5opaque::events::has_events($o), '... no events anymore');

    P5opaque::events::fire($o, 'test');
    is(P5opaque::slots::get($o, "test"), 1, '... test event was not fired again');
}

=pod

{
    my $o = P5opaque::newOV();
    Dump($o);

    ok(!P5opaque::events::has_events($o), '... no events yet');

    my @tests;
    my @events;
    foreach my $i (0 .. 10) {
        $tests[$i]  = 0;
        $events[$i] = sub { $tests[$i]++ };

        P5opaque::events::bind($o, 'test', $events[$i]);
    }

    ok(P5opaque::events::has_events($o), '... have events now');
    is($tests[$_], 0, '... test ('.$_.') event has not been fired')
        foreach 0 .. 10;

    P5opaque::events::fire($o, 'test');
    P5opaque::events::fire($o, 'test');
    P5opaque::events::fire($o, 'test');

    is($tests[$_], 3, '... test ('.$_.') event has not been fired')
        foreach 0 .. 10;
}
=cut

done_testing;

