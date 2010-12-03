#!/usr/bin/perl
# tcpserver.pl — минимальный ident-сервер (RFC 1413).
#
# Протокол ident позволяет удалённому серверу узнать имя пользователя,
# которому принадлежит TCP-соединение. Клиент присылает пару портов
# «<порт на нашей стороне>, <порт на его стороне>», сервер отвечает
# «<порт>, <порт> : USERID : <ОС> : <имя пользователя>».
#
# Скрипт на любой корректный запрос возвращает одно и то же имя
# пользователя. Параметры задаются переменными окружения:
#   IDENT_HOST    — адрес для прослушивания (по умолчанию 0.0.0.0)
#   IDENT_PORT    — порт (по умолчанию 113)
#   IDENT_USER    — возвращаемое имя пользователя
#   IDENT_OS      — тип ОС в ответе (по умолчанию WIN32)
#   IDENT_TIMEOUT — таймаут ожидания запроса в секундах (по умолчанию 10)

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

my $host    = $ENV{IDENT_HOST}    // '0.0.0.0';
my $port    = $ENV{IDENT_PORT}    // 113;
my $user    = $ENV{IDENT_USER}    // 'ldap_ruslan1001';
my $os      = $ENV{IDENT_OS}      // 'WIN32';
my $timeout = $ENV{IDENT_TIMEOUT} // 10;

# RFC 1413 ограничивает длину запроса 1000 символами
use constant MAX_REQUEST => 1000;

$| = 1;

my $server = IO::Socket::INET->new(
  LocalHost => $host,
  LocalPort => $port,
  Proto     => 'tcp',
  Listen    => 5,
  ReuseAddr => 1,
) or die "Ошибка создания сокета на $host:$port: $!\n";

print "Ожидание соединений на $host:$port\n";

while (1) {
  my $client = $server->accept() or next;
  my ($peer_host, $peer_port) = ($client->peerhost, $client->peerport);
  print "Соединение от $peer_host:$peer_port\n";

  my $request = read_line($client, $timeout);
  if (!defined $request) {
    print "Запрос не получен (таймаут или разрыв соединения)\n";
  } else {
    # Управляющие символы в логе заменяются, чтобы не портить вывод
    (my $shown = $request) =~ s/[^\x20-\x7E]/?/g;
    print "Получен запрос: $shown\n";

    if ($request =~ /^\s*(\d+)\s*,\s*(\d+)\s*$/) {
      my ($local, $remote) = ($1, $2);
      my $reply = valid_port($local) && valid_port($remote)
        ? "$local, $remote : USERID : $os : $user"
        : "$local, $remote : ERROR : INVALID-PORT";
      print $client "$reply\r\n";
      print "Отправлен ответ: $reply\n";
    } else {
      print "Некорректный запрос, соединение закрыто\n";
    }
  }
  close $client;
}

# Чтение одной строки с таймаутом. IO::Select используется вместо alarm,
# так как alarm на Windows не прерывает блокирующее чтение из сокета.
sub read_line {
  my ($sock, $limit) = @_;
  my $sel      = IO::Select->new($sock);
  my $deadline = time + $limit;
  my $buf      = '';

  while ($buf !~ /\n/ && length $buf < MAX_REQUEST) {
    my $left = $deadline - time;
    return undef if $left <= 0 || !$sel->can_read($left);
    my $n = sysread($sock, $buf, MAX_REQUEST - length $buf, length $buf);
    return undef unless $n;
  }
  $buf =~ s/\r?\n.*//s;
  return $buf;
}

sub valid_port {
  my ($p) = @_;
  return $p >= 1 && $p <= 65535;
}
