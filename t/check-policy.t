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
                'Prefer using module module Something::Else over FindBin',
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
                'Prefer using module module Something::Else over FindBin',
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
                'Prefer using module module Something::Else over FindBin',
                'relax this is just a test'
            ],
            [
                'Prefer using module module XML::Simple over XML::LibXML',
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

done_testing;

sub _massage_violations {
    my (@violations) = @_;

    return [ map { [ $_->description, $_->explanation ] } @violations ];
}

1;
