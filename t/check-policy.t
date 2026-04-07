#!perl

use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Explain;
use Test2::Plugin::NoWarnings;

use File::Temp qw( tempdir );
use File::Spec ();

use Perl::Critic::Policy::PreferredModules ();
use Perl::Critic                           ();

my $tmpdir     = tempdir( CLEANUP => 1 );
my $profile_rc = File::Spec->catfile( $tmpdir, 'profile.rc' );
my $config_ini = File::Spec->catfile( $tmpdir, 'preferred_modules.ini' );

sub _write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}

_write_file( $profile_rc, <<"EOS" );
severity = 1
verbose  = 8

[PreferredModules]
config = $config_ini
EOS

{
    ok(
        dies {

            Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            );

        },
        "Cannot load a policy without a configuration file"
    );
}

_write_file( $config_ini, <<EOS );
[Do::Not::Recommend]
prefer = Another::Package
reason = Please prefer using Another::Package rather than package Do::Not::Recommend
EOS

my $critic = Perl::Critic->new(
    '-profile'       => $profile_rc,
    '-single-policy' => 'PreferredModules'
);

{
    my @policies = $critic->policies;
    is \@policies, ['PreferredModules'], "only PreferredModules is enabled"
      or diag explain \@policies;
}

{

    _write_file( $config_ini, <<EOS );
[Do::Not::Recommend]
prefer = Another::Package
reason = Please prefer using Another::Package rather than package Do::Not::Recommend
[Foo]
[Bar]
[OnlyPrefer]
prefer=X
[OnlyReason]
reason=X
EOS

    $critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

}

{    # using invalid args

    _write_file( $config_ini, <<EOS );
[Do::Not::Recommend]
boom = Unknown arg
EOS

    like(
        dies {
            $critic = Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{Perl::Critic::Policy::PreferredModules Invalid configuration - Package 'Do::Not::Recommend' is using an unknown setting 'boom'},
        "Throw exception on unknown settings"
    );

}

{    # using invalid INI syntax

    _write_file( $config_ini, <<EOS );
[Do::Not::Recommend
this is not valid INI
EOS

    like(
        dies {
            $critic = Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{Perl::Critic::Policy::PreferredModules Invalid configuration file},
        "Throw exception on invalid INI content"
    );

}

## Shared init

_write_file( $config_ini, <<EOS );
[FindBin]
prefer = Something::Else
reason = relax this is just a test
[XML::LibXML]
prefer = XML::Simple
[XML::DOM]
EOS

$critic = Perl::Critic->new(
    '-profile'       => $profile_rc,
    '-single-policy' => 'PreferredModules'
);

{
    my $code = <<'EOS';
package My::Package;

use CPAN;

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 0, "nothing critic here";
}

{
    my $code = <<'EOS';
package My::Package;

use FindBin;

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 1, "use FindBin is a violation";

    is(
        _massage_violations(@violations),
        [
            [
                'Prefer using module Something::Else over FindBin',
                'relax this is just a test'
            ]
        ],
        'violations description & explanation'
    );
}

{
    my $code = <<'EOS';
package My::Package;

require FindBin;

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 1, "require FindBin is a violation";

    is(
        _massage_violations(@violations),
        [
            [
                'Prefer using module Something::Else over FindBin',
                'relax this is just a test'
            ]
        ],
        'violations description & explanation'
    );
}

{
    my $code = <<'EOS';
package My::Package;

use FindBin;
use Cwd;
use XML::LibXML ();
use XML::DOM    qw( :all );

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 3, "3 violations";

    is(
        _massage_violations(@violations),
        [
            [
                'Prefer using module Something::Else over FindBin',
                'relax this is just a test'
            ],
            [
                'Prefer using module XML::Simple over XML::LibXML',
                'Using module XML::LibXML is not recommended'
            ],
            [
                'Using module XML::DOM is not recommended',
                'Using module XML::DOM is not recommended'
            ]
        ],
        'violations description & explanation'
    );
}

{
    note "'no Module' should not trigger violations";

    my $code = <<'EOS';
package My::Package;

no FindBin;

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 0, "no FindBin does not trigger a violation";
}

{
    note "'no' and 'use' of same module";

    my $code = <<'EOS';
package My::Package;

use FindBin;
no FindBin;

1;
EOS

    my @violations = $critic->critique( \$code );
    is scalar @violations => 1, "only 'use' triggers, not 'no'";
}

# severity override tests

{
    note "severity override per module";

    _write_file( $config_ini, <<EOS );
[FindBin]
prefer = Something::Else
reason = relax this is just a test
severity = 5
[XML::LibXML]
prefer = XML::Simple
[XML::DOM]
severity = 1
EOS

    my $sev_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    {
        my $code = <<'EOS';
package My::Package;

use FindBin;

1;
EOS

        my @violations = $sev_critic->critique( \$code );
        is scalar @violations => 1, "FindBin violation with severity override";
        is $violations[0]->severity, 5, "severity overridden to 5 for FindBin";
    }

    {
        my $code = <<'EOS';
package My::Package;

use XML::DOM;

1;
EOS

        my @violations = $sev_critic->critique( \$code );
        is scalar @violations => 1, "XML::DOM violation with severity override";
        is $violations[0]->severity, 1, "severity overridden to 1 for XML::DOM";
    }

    {
        my $code = <<'EOS';
package My::Package;

use XML::LibXML;

1;
EOS

        my @violations = $sev_critic->critique( \$code );
        is scalar @violations => 1, "XML::LibXML violation without severity override";
        is $violations[0]->severity, 3, "default severity (3) for XML::LibXML";
    }
}

{
    note "invalid severity value";

    _write_file( $config_ini, <<EOS );
[Bad::Module]
severity = 9
EOS

    like(
        dies {
            Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{invalid severity '9'},
        "Throw exception on invalid severity value"
    );
}

# message override tests

{
    note "message key replaces auto-generated description";

    _write_file( $config_ini, <<EOS );
[FindBin]
prefer = Something::Else
reason = relax this is just a test
message = Do not use FindBin - see internal wiki
EOS

    my $msg_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    my $code = <<'EOS';
package My::Package;

use FindBin;

1;
EOS

    my @violations = $msg_critic->critique( \$code );
    is scalar @violations => 1, "FindBin violation with message override";

    is(
        _massage_violations(@violations),
        [
            [
                'Do not use FindBin - see internal wiki',
                'relax this is just a test'
            ]
        ],
        'message overrides auto-generated description, reason still used as explanation'
    );
}

{
    note "message key without prefer or reason";

    _write_file( $config_ini, <<EOS );
[Bad::Module]
message = This module is forbidden by policy
EOS

    my $msg_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    my $code = <<'EOS';
package My::Package;

use Bad::Module;

1;
EOS

    my @violations = $msg_critic->critique( \$code );
    is scalar @violations => 1, "Bad::Module violation with message only";

    is(
        _massage_violations(@violations),
        [
            [
                'This module is forbidden by policy',
                'Using module Bad::Module is not recommended'
            ]
        ],
        'message replaces description, default explanation used when no reason'
    );
}

{
    note "message key combined with severity override";

    _write_file( $config_ini, <<EOS );
[Dangerous::Module]
message = CRITICAL: Do not use this module
severity = 5
EOS

    my $msg_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    my $code = <<'EOS';
package My::Package;

use Dangerous::Module;

1;
EOS

    my @violations = $msg_critic->critique( \$code );
    is scalar @violations => 1, "Dangerous::Module violation with message + severity";
    is $violations[0]->severity, 5, "severity override works with message";

    is(
        _massage_violations(@violations),
        [
            [
                'CRITICAL: Do not use this module',
                'Using module Dangerous::Module is not recommended'
            ]
        ],
        'message and severity work together'
    );
}

{
    note "non-numeric severity value";

    _write_file( $config_ini, <<EOS );
[Bad::Module]
severity = high
EOS

    like(
        dies {
            Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{invalid severity 'high'},
        "Throw exception on non-numeric severity value"
    );
}

SKIP: {
    skip "chmod has no effect for root", 1 if $> == 0;

    note "unreadable config file";

    my $unreadable = File::Spec->catfile( $tmpdir, 'unreadable.ini' );
    _write_file( $unreadable, "[Foo]\n" );
    chmod 0000, $unreadable;

    my $unreadable_rc = File::Spec->catfile( $tmpdir, 'unreadable.rc' );
    _write_file( $unreadable_rc, <<"EOS" );
severity = 1
[PreferredModules]
config = $unreadable
EOS

    like(
        dies {
            Perl::Critic->new(
                '-profile'       => $unreadable_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{Cannot open config file},
        "Throw exception when config file is unreadable"
    );

    chmod 0644, $unreadable;    # restore for cleanup
}

{
    note "Config::INI root section ignored";

    _write_file( $config_ini, <<EOS );
reason = global default

[FindBin]
prefer = Something::Else
reason = use Something::Else instead
EOS

    my $root_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    {
        my $code = <<'EOS';
package My::Package;

use _;

1;
EOS

        my @violations = $root_critic->critique( \$code );
        is scalar @violations => 0,
          "root section '_' from Config::INI is not treated as a module";
    }

    {
        my $code = <<'EOS';
package My::Package;

use FindBin;

1;
EOS

        my @violations = $root_critic->critique( \$code );
        is scalar @violations => 1, "named sections still match normally";
    }
}

done_testing;

sub _massage_violations {
    my (@violations) = @_;

    return [ map { [ $_->description, $_->explanation ] } @violations ];
}

1;
