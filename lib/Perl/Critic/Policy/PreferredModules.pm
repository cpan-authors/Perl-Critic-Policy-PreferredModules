package Perl::Critic::Policy::PreferredModules;

use strict;
use warnings;

use parent 'Perl::Critic::Policy';

use Perl::Critic::Utils qw{ :severities :classification :ppi $SEVERITY_MEDIUM $TRUE $FALSE };

use Perl::Critic::Exception::AggregateConfiguration ();
use Perl::Critic::Exception::Configuration::Generic ();

use Config::INI::Reader ();

sub supported_parameters {
    return (
        {
            name        => 'config',
            description => 'Config::INI file listing recommendations.',
            behavior    => 'string',
        },
    );
}

use constant default_severity => $SEVERITY_MEDIUM;
use constant applies_to       => 'PPI::Statement::Include';

use constant optional_config_attributes => qw{ prefer reason severity message };

# VERSION
# ABSTRACT: Provide custom package recommendations

sub initialize_if_enabled {
    my ( $self, $config ) = @_;

    my $cfg_file = $config->get('config') // '';
    $cfg_file =~ s{^~}{$ENV{HOME}};

    $self->{_is_enabled} = !! $self->_parse_config($cfg_file);

    return $TRUE;
}

sub _add_exception {
    my ( $self, $msg ) = @_;

    $msg //= q[Unknown Error];

    $msg = __PACKAGE__ . ' ' . $msg;

    my $errors = Perl::Critic::Exception::AggregateConfiguration->new();

    $errors->add_exception( Perl::Critic::Exception::Configuration::Generic->throw( message => $msg ) );

    return;
}

sub _parse_config {
    my ( $self, $cfg_file ) = @_;

    if ( !length $cfg_file ) {
        return;
    }

    if ( !-e $cfg_file ) {
        return $self->_add_exception(qq[config file '$cfg_file' does not exist.]);
    }

    my $content;
    {
        local $/;
        open my $fh, '<', $cfg_file
            or return $self->_add_exception(qq[Cannot open config file '$cfg_file': $!]);
        $content = <$fh>;
    }

    my $preferred_cfg;
    eval { $preferred_cfg = Config::INI::Reader->read_string($content); 1 } or do {
        return $self->_add_exception(qq[Invalid configuration file $cfg_file]);
    };

    my %valid_opts    = map { $_ => 1 } optional_config_attributes();

    # Config::INI uses '_' for the root/default section — skip it
    delete $preferred_cfg->{'_'};

    foreach my $pkg ( keys %$preferred_cfg ) {
        my $setup = $preferred_cfg->{$pkg};

        my @has_opts = keys %$setup;
        foreach my $opt (@has_opts) {
            next if $valid_opts{$opt};
            $self->_add_exception("Invalid configuration - Package '$pkg' is using an unknown setting '$opt'");
        }

        if ( defined $setup->{severity} ) {
            my $sev = $setup->{severity};
            if ( $sev !~ /\A[1-5]\z/ ) {
                $self->_add_exception("Invalid configuration - Package '$pkg' has invalid severity '$sev' (must be 1-5)");
            }
        }
    }

    $self->{_cfg_preferred_modules} = $preferred_cfg;

    return 1;
}

sub violates {
    my ( $self, $elem ) = @_;

    return () unless $self->{_is_enabled};
    return () unless $elem;

    my $module = $elem->module;

    return () unless defined $module;
    return () unless my $setup = $self->{_cfg_preferred_modules}->{$module};

    my $desc = qq[Using module $module is not recommended];
    my $expl = $setup->{reason} // $desc;

    if ( defined $setup->{message} ) {
        $desc = $setup->{message};
    }
    elsif ( my $prefer = $setup->{prefer} ) {
        $desc = "Prefer using module $prefer over $module";
    }

    if ( my $sev = $setup->{severity} ) {
        local $self->{_severity} = $sev;
        return $self->violation( $desc, $expl, $elem );
    }

    return $self->violation( $desc, $expl, $elem );
}

1;

__END__

=pod

=encoding UTF-8

=head1 DESCRIPTION

Every project has its own rules for preferring specific packages over others.

This Policy tries to be `un-opinionated` and let the user provide a module
preferences with an explanation and/or suggested alternative.

=head1 MODULES

=head1 CONFIGURATION

To use L<Perl::Critic::Policy::PreferredModules> you have first to enable it in your
 F<.perlcriticrc> file by providing a F<preferred_modules.ini> configuration file:

    [PreferredModules]
    config = /path/to/preferred_modules.ini
    # you can also use '~' in the path for $HOME
    #config = ~/.preferred_modules

The  F<preferred_modules.ini> file is using the L<Config::INI> format and can looks like this

    [Do::Not::Use]
    prefer = Another::Package
    reason = "Please use Another::Package rather than Do::Not::Use"

    [Avoid::Using::This]
    [And::Also::That]

    [No:Reason]
    prefer=A::Better:Module
    
    [Only::Reason]
    reason="If you use this module, a puppy might die."

    [Hard::Ban]
    severity=5
    reason="This module has known security vulnerabilities"

    [Custom::Message]
    message="Do not use Custom::Message - see internal wiki for details"

Each module entry supports the following optional keys:

=over 4

=item C<prefer> - Suggested replacement module

=item C<reason> - Explanation shown in the violation message

=item C<severity> - Override the policy's default severity for this module (1-5, where 5 is most severe)

=item C<message> - Free-form description that fully replaces the auto-generated violation text

=back

=head1 SEE ALSO

L<Perl::Critic>

=cut
