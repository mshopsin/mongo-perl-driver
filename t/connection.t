use strict;
use warnings;
use Test::More;
use Test::Exception;

use MongoDB::Timestamp; # needed if db is being run as master

use MongoDB;

my $conn;
eval {
    my $host = "localhost";
    if (exists $ENV{MONGOD}) {
        $host = $ENV{MONGOD};
    }
    $conn = MongoDB::Connection->new(host => $host, ssl => $ENV{MONGO_SSL});
};

if ($@) {
    plan skip_all => $@;
}
else {
    plan tests => 19;
}

throws_ok {
    MongoDB::Connection->new(host => 'localhost', port => 1, ssl => $ENV{MONGO_SSL});
} qr/couldn't connect to server/, 'exception on connection failure';

SKIP: {
    skip "connecting to default host/port won't work with a remote db", 6 if exists $ENV{MONGOD};

    lives_ok {
        $conn = MongoDB::Connection->new(ssl => $ENV{MONGO_SSL});
    } 'successful connection';
    isa_ok($conn, 'MongoDB::Connection');

    is($conn->host, 'mongodb://localhost:27017', 'host default value');

    # just make sure a couple timeouts work
    my $to = MongoDB::Connection->new('timeout' => 1, ssl => $ENV{MONGO_SSL});
    $to = MongoDB::Connection->new('timeout' => 123, ssl => $ENV{MONGO_SSL});
    $to = MongoDB::Connection->new('timeout' => 2000000, ssl => $ENV{MONGO_SSL});

    # test conn format
    lives_ok {
        $conn = MongoDB::Connection->new("host" => "mongodb://localhost:27017", ssl => $ENV{MONGO_SSL});
    } 'connected';

    lives_ok {
        $conn = MongoDB::Connection->new("host" => "mongodb://localhost:27017,", ssl => $ENV{MONGO_SSL});
    } 'extra comma';

    lives_ok {
        my $ip = 27020;
        while ((exists $ENV{DB_PORT} && $ip eq $ENV{DB_PORT}) ||
               (exists $ENV{DB_PORT2} && $ip eq $ENV{DB_PORT2})) {
            $ip++;
        }
        $conn = MongoDB::Connection->new("host" => "mongodb://localhost:".$ip.",localhost:".($ip+1).",localhost", ssl => $ENV{MONGO_SSL});
    } 'last in line';
}

my $db = $conn->get_database('test_database');
isa_ok($db, 'MongoDB::Database', 'get_database');

$db->get_collection('test_collection')->insert({ foo => 42 }, {safe => 1});

ok((grep { $_ eq 'test_database' } $conn->database_names), 'database_names');

my $result = $db->drop;
is(ref $result, 'HASH', $result);
is($result->{'ok'}, 1, 'db was dropped');

# TODO: won't work on master/slave until SERVER-2329 is fixed
# ok(!(grep { $_ eq 'test_database' } $conn->database_names), 'database got dropped');


# w
SKIP: {
    is($conn->w, 1, "get w");
    $conn->w(3);
    is($conn->w, 3, "set w");

    is($conn->wtimeout, 1000, "get wtimeout");
    $conn->wtimeout(100);
    is($conn->wtimeout, 100, "set wtimeout");

    $db->drop;
}

# autoload
{
    my $db1 = $conn->foo;
    is($db1->name, "foo");
}

# query_timeout
{
    my $timeout = $MongoDB::Cursor::timeout;

    my $conn2 = MongoDB::Connection->new(auto_connect => 0, ssl => $ENV{MONGO_SSL});
    is($conn2->query_timeout, $timeout, 'query timeout');

    $MongoDB::Cursor::timeout = 40;
    $conn2 = MongoDB::Connection->new(auto_connect => 0, ssl => $ENV{MONGO_SSL});
    is($conn2->query_timeout, 40, 'query timeout');

    $MongoDB::Cursor::timeout = $timeout;
}

# max_bson_size
{
    my $size = $conn->max_bson_size;
    my $result = $conn->admin->run_command({buildinfo => 1});
    if (exists $result->{'maxBsonObjectSize'}) {
        is($size, $result->{'maxBsonObjectSize'});
    }
    else {
        is($size, 4*1024*1024);
    }
}

END {
    if ($conn) {
        $conn->foo->drop;
    }
    if ($db) {
        $db->drop;
    }
}
