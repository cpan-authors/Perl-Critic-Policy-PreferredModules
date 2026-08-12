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

{
    note "multiple config errors reported together";

    _write_file( $config_ini, <<EOS );
[Alpha::Module]
boom = bad option
severity = 99

[Beta::Module]
fizz = another bad option
EOS

    my $err = dies {
        Perl::Critic->new(
            '-profile'       => $profile_rc,
            '-single-policy' => 'PreferredModules'
        )
    };
    ok $err, "Throws on multiple config errors";
    like $err, qr{Alpha::Module.*unknown setting 'boom'},
        "Reports unknown setting for Alpha";
    like $err, qr{Alpha::Module.*invalid severity '99'},
        "Reports invalid severity for Alpha";
    like $err, qr{Beta::Module.*unknown setting 'fizz'},
        "Reports unknown setting for Beta";
}

# parent/base module argument checking

{
    note "use parent module checking";

    _write_file( $config_ini, <<EOS );
[Banned::Parent]
prefer = Good::Parent
reason = Banned::Parent has issues
[Another::Bad]
EOS

    my $parent_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    {
        my $code = <<'EOS';
package My::Package;
use parent 'Banned::Parent';
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 1, "use parent catches banned module in arguments";
        like $violations[0]->description, qr/Banned::Parent/, "violation mentions the parent module";
    }

    {
        my $code = <<'EOS';
package My::Package;
use base 'Banned::Parent';
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 1, "use base catches banned module in arguments";
    }

    {
        my $code = <<'EOS';
package My::Package;
use parent qw(Banned::Parent Another::Bad);
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 2, "use parent qw() catches multiple banned parents";
    }

    {
        my $code = <<'EOS';
package My::Package;
use parent -norequire, 'Banned::Parent';
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 1, "use parent -norequire still catches banned parent";
    }

    {
        my $code = <<'EOS';
package My::Package;
use parent 'Safe::Module';
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 0, "use parent with non-banned module is fine";
    }

    {
        my $code = <<'EOS';
package My::Package;
use parent 'Banned::Parent', 'Safe::Module';
1;
EOS

        my @violations = $parent_critic->critique( \$code );
        is scalar @violations => 1, "use parent with mix of banned and safe catches only banned";
    }
}

# partial preferences: the 'for' key

{
    note "partial preference using 'for'";

    _write_file( $config_ini, <<EOS );
[File::Slurper]
prefer = File::Slurper::Temp
for = write_binary write_text
reason = File::Slurper::Temp writes atomically
EOS

    my $for_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper qw{ write_text };

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 1, "importing a listed function is a violation";

        is(
            _massage_violations(@violations),
            [
                [
                    'Prefer using module File::Slurper::Temp over File::Slurper for write_binary, write_text',
                    'File::Slurper::Temp writes atomically'
                ]
            ],
            'violation mentions the functions it applies to'
        );
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper qw{ read_text read_binary };

my $content = read_text($file);

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 0, "importing only unlisted functions is fine";
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper qw{ read_text write_binary };

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 1, "a single listed function among others is a violation";
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper 'write_text';

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 1, "quoted import list is honored";
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper;

write_text( $file, $content );

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 1, "call to a listed function without an import list is a violation";
    }

    {
        my $code = <<'EOS';
package My::Package;

require File::Slurper;

File::Slurper::write_binary( $file, $content );

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 1, "fully qualified call to a listed function is a violation";
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper;

my $content = File::Slurper::read_text($file);

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 0, "no listed function used, no violation";
    }

    {
        my $code = <<'EOS';
package My::Package;

use File::Slurper ();

my $obj = Some::Object->write_text($file);

1;
EOS

        my @violations = $for_critic->critique( \$code );
        is scalar @violations => 0, "a method call is not a function call";
    }
}

{
    note "'for' without prefer";

    _write_file( $config_ini, <<EOS );
[XML::LibXML]
for = parse_html_string
EOS

    my $for_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    my $code = <<'EOS';
package My::Package;

use XML::LibXML qw{ parse_html_string };

1;
EOS

    my @violations = $for_critic->critique( \$code );
    is scalar @violations => 1, "'for' works without a prefer entry";

    is(
        _massage_violations(@violations),
        [
            [
                'Using module XML::LibXML is not recommended for parse_html_string',
                'Using module XML::LibXML is not recommended'
            ]
        ],
        'violation description'
    );
}

{
    note "comma separated 'for' list";

    _write_file( $config_ini, <<EOS );
[File::Slurper]
prefer = File::Slurper::Temp
for = write_binary, write_text
EOS

    my $for_critic = Perl::Critic->new(
        '-profile'       => $profile_rc,
        '-single-policy' => 'PreferredModules'
    );

    my $code = <<'EOS';
package My::Package;

use File::Slurper qw{ write_binary };

1;
EOS

    my @violations = $for_critic->critique( \$code );
    is scalar @violations => 1, "comma separated list is honored";
}

{
    note "empty 'for' value";

    _write_file( $config_ini, <<EOS );
[Bad::Module]
for =
EOS

    like(
        dies {
            Perl::Critic->new(
                '-profile'       => $profile_rc,
                '-single-policy' => 'PreferredModules'
            )
        },
        qr{has an empty 'for' list},
        "Throw exception on an empty 'for' list"
    );
}

done_testing;

sub _massage_violations {
    my (@violations) = @_;

    return [ map { [ $_->description, $_->explanation ] } @violations ];
}

1;
