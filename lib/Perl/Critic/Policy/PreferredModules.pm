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

sub _throw {
    my ( $self, $msg ) = @_;

    Perl::Critic::Exception::Configuration::Generic->throw(
        message => __PACKAGE__ . ' ' . ( $msg // 'Unknown Error' ),
    );
}

sub _parse_config {
    my ( $self, $cfg_file ) = @_;

    if ( !length $cfg_file ) {
        return;
    }

    if ( !-e $cfg_file ) {
        $self->_throw(qq[config file '$cfg_file' does not exist.]);
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
        $self->_throw(qq[Invalid configuration file $cfg_file]);
    };

    my %valid_opts = map { $_ => 1 } optional_config_attributes();
    my $errors     = Perl::Critic::Exception::AggregateConfiguration->new();

    # Config::INI uses '_' for the root/default section — skip it
    delete $preferred_cfg->{'_'};

    foreach my $pkg ( sort keys %$preferred_cfg ) {
        my $setup = $preferred_cfg->{$pkg};

        foreach my $opt ( keys %$setup ) {
            next if $valid_opts{$opt};
            $errors->add_exception(
                Perl::Critic::Exception::Configuration::Generic->new(
                    message => __PACKAGE__ . " Invalid configuration - Package '$pkg' is using an unknown setting '$opt'",
                )
            );
        }

        if ( defined $setup->{severity} ) {
            my $sev = $setup->{severity};
            if ( $sev !~ /\A[1-5]\z/ ) {
                $errors->add_exception(
                    Perl::Critic::Exception::Configuration::Generic->new(
                        message => __PACKAGE__ . " Invalid configuration - Package '$pkg' has invalid severity '$sev' (must be 1-5)",
                    )
                );
            }
        }
    }

    die $errors if $errors->has_exceptions();

    $self->{_cfg_preferred_modules} = $preferred_cfg;

    return 1;
}

sub violates {
    my ( $self, $elem ) = @_;

    return () unless $self->{_is_enabled};
    return () unless $elem;

    # 'no Module' unloads/disables — not a use violation
    my $type = $elem->type;
    return () if defined $type && $type eq 'no';

    my $module = $elem->module;

    return () unless defined $module;

    my @violations;

    if ( my $setup = $self->{_cfg_preferred_modules}->{$module} ) {
        push @violations, $self->_build_violation( $module, $setup, $elem );
    }

    # Also check modules passed as arguments to 'use parent' / 'use base'
    if ( $module eq 'parent' || $module eq 'base' ) {
        for my $parent_mod ( $self->_extract_parent_modules($elem) ) {
            next unless my $setup = $self->{_cfg_preferred_modules}->{$parent_mod};
            push @violations, $self->_build_violation( $parent_mod, $setup, $elem );
        }
    }

    return @violations;
}

sub _build_violation {
    my ( $self, $module, $setup, $elem ) = @_;

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

sub _extract_parent_modules {
    my ( $self, $elem ) = @_;

    my @modules;
    for my $child ( $elem->schildren ) {
        if ( $child->isa('PPI::Token::Quote') ) {
            my $val = $child->string;
            push @modules, $val if $val =~ /\A[A-Za-z_]\w*(?:::\w+)*\z/;
        }
        elsif ( $child->isa('PPI::Token::QuoteLike::Words') ) {
            push @modules, grep { /\A[A-Za-z_]\w*(?:::\w+)*\z/ } $child->literal;
        }
    }
    return @modules;
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

=head1 PARENT AND BASE CLASS CHECKING

When the policy encounters C<use parent> or C<use base> statements, it also
checks the modules passed as arguments. For example, if C<Banned::Module> is
in your configuration file, all of these will trigger a violation:

    use Banned::Module;
    use parent 'Banned::Module';
    use base qw(Banned::Module);
    use parent -norequire, 'Banned::Module';

=head1 SEE ALSO

L<Perl::Critic>

=cut
