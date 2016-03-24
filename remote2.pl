#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
$Data::Dumper::Indent=0;
use Linux::Input;
use IO::Socket::INET;
my %eventhash;

#use evtest to get list of possible input events
parseEventFile();
debug( Dumper(\%eventhash) . "\n");

my %secondaryMap=(
  1=>"One",
  2=>"Two",
  3=>"Three",
  4=>"Four",
  5=>"Five",
  6=>"Six",
  7=>"Seven",
  8=>"Eight",
  9=>"Nine",
  0=>"Zero",
  "Enter"=>"Select",
  "Playpause"=>"Play",
  "Backspace"=>"Back",
  "A"=>"YouView",
  "S"=>"Power",
);


my $inputs;
my $count=1;
debug( "Looking for flirc driver...\n");
do {
   debug( "  attempt $count\n");
   sleep 10 if $count>1;
   $inputs=`ls /dev/input/by-id/*flirc* 2>&1`;
   $count++;
} until ($inputs!~/cannot access/);

debug( "flirc found\n");

my $flirc=Linux::Input->new("/dev/input/by-id/usb-flirc.tv_flirc-event-kbd");

my $ir_host="whitebrick";
debug( "looking for $ir_host:8765...\n");
$count=1;
my $socket;
do {
   debug( "  attempt $count\n");
   sleep 10 if $count>1;
   $socket = new IO::Socket::INET (
       PeerHost => $ir_host,
       PeerPort => '8765',
       Proto => 'tcp',
   );
   $count++;
} until ($socket);

debug( "connected to $ir_host \n");


while (1) {
    while (my @events = $flirc->poll(0.01)) {
      foreach (@events) {
         debug(Dumper($_) ."\n");
         my $button=$eventhash{$_->{code}};
         $button = "" if (!defined $button);
         next if $_->{value} ne 1; #I think value is number of repeats, get lots of KEY_3 with massive values
         if ($button && $button ne "") {  
          action($button);
         } else {
           warn "can't handle this event:$_->{code}\n";
         }
      }
    }
}

sub parseEventFile {
   while (<>) {
     chomp $_;
     my ($code,$name)=$_=~/Event code (\d*) \((\w*)\)/;
     next if !$code; 
     next if !$name;
     $eventhash{$code}=$name;
   }
}

sub camel {
  my ($button)=@_;
  my ($f,$rest)=$button=~/(\w)(.*)/;
  $rest=lc $rest;
  $f=uc $f;
  my $new=$f . $rest;
  return $new; 
}

sub map_key {
  my ($button)=@_;
debug( "button in:$button\n");
  $button=~s/KEY_//g;
  $button=camel($button);
  if ($secondaryMap{$button}){
    $button=$secondaryMap{$button};
  } 
  return $button;
}

sub remote_action {
   my ($new_button)=@_;
   if ($socket) {
      debug( "socket is open\n");
      my $cmd="SEND_ONCE bt2 $new_button";
      debug( "Send:'$cmd'...\n");
      $socket->send($cmd . "\n");
      my $response="";
      my $count=50;
      do {
	 $socket->recv($response, 1024);
	 debug( $response . "\n");
          $count--;
      } until ($response=~/SUCCESS|ERROR/ || $count <=0);
      if ($count <=0) {
        warn "Hit max tries for response\n";
      } elsif ($response=~/ERROR/) {
        warn "Failed to handle command\n";
      }
   } else {
      warn "Socket appears to have disconnected\n";
   }
}

sub action {
  my ($button)=@_;
  #need to decide focus here
  my $new_button=map_key($button);
  debug( "button:$button, mapped to $new_button\n");
  if (chrome_running()) {
      debug( "chrome is running\n");
      if ($new_button eq "Apostrophe") {
         kill_chrome();
      } else {
         debug( "send to socket\n");
         remote_action($new_button);
      }
  }
}

sub kill_chrome {
  my @ps=`ps -eaf | grep chrome | grep -v "grep"`;
  debug( "kill chrome, pids:");
  foreach my $psr (@ps) {
    my ($user,$p1,$p2)=split(" ",$psr);
    debug( "   $p1\n");
    `kill $p1`;
  }
  debug("\n");
}

sub chrome_running {
  my @ps=`ps -eaf | grep chrome | grep -v "grep"`;
  if (scalar @ps>0) {
    return 1;
  } else {
     return 0;
  }
}

sub debug {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
   printf "%02d:%02d:%02d %s",$hour,$min,$sec,$_[0];

}
