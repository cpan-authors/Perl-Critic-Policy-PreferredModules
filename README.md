# NAME

Perl::Critic::Policy::PreferredModules - Provide custom package recommendations

# VERSION

version 0.005

# DESCRIPTION

Every project has its own rules for preferring specific packages over others.

This Policy tries to be \`un-opinionated\` and let the user provide a module
preferences with an explanation and/or suggested alternative.

# MODULES

# CONFIGURATION

To use [Perl::Critic::Policy::PreferredModules](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3APolicy%3A%3APreferredModules) you have first to enable it in your
 `.perlcriticrc` file by providing a `preferred_modules.ini` configuration file:

```perl
[PreferredModules]
config = /path/to/preferred_modules.ini
# you can also use '~' in the path for $HOME
#config = ~/.preferred_modules
```

The  `preferred_modules.ini` file is using the [Config::INI](https://metacpan.org/pod/Config%3A%3AINI) format and can looks like this

```perl
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
```

Each module entry supports the following optional keys:

- `prefer` - Suggested replacement module
- `reason` - Explanation shown in the violation message
- `severity` - Override the policy's default severity for this module (1-5, where 5 is most severe)

# SEE ALSO

[Perl::Critic](https://metacpan.org/pod/Perl%3A%3ACritic)

# AUTHOR

Nicolas R <atoomic@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by cPanel, L.L.C.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
