use inc::Module::Install;
name 'WWW-Sherdog';
all_from 'lib/WWW/Sherdog.pm';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
