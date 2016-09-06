#!/usr/bin/perl  -wT
#
# 
# $Id: gpg-aliases.pl,v 1.8 2006/11/21 18:09:52 paco Exp $
#
# Script for encrypted mailing lists with gpg
#
# See configuration and reamd files

use strict ;
use locale ;
use Net::LDAP;


# And define the allowed ENV for taint operation
$ENV{'PATH'} = '' ;
$ENV{'BASH_ENV'} = '' ;
$ENV{'LC_ALL'} = 'en_EN' ;
$ENV{'LANG'} = 'en_EN' ;
$ENV{'LC_CTYPE'} = 'en_EN' ;

# temporaly files
my $tmp1="/tmp/tmp1-encryptedmail.$$" ;
my $tmp2="/tmp/tmp2-desencrytedmail.$$" ;
my $tmp3="/tmp/tmp3-messagebody-to-send.$$" ;
my $tmp4="/tmp/tmp4-encryptedmailto-to-send.$$" ;
my $tmp5="/tmp/tmp5-gnupgoutput.$$" ;

# LDAP variables
my ($useldap  , $ldapfilter, $ldapfieldsep , $ldapkeyid , $ldapaddress, $ldapserver ,$ldaplistname,
	$ldapbase, $ldapattribute, $ldaplistpos, $ldapseparator) ;

my $debug = "0" ;
my ($pgpdir, $gpg) ;

# Global variables
my $logfile ="./default-log.txt" ;
my $miaddr ;
my $sendmail ;
my %config ;
my @tmp ;
my $i ;
my $j ;
my $re ;
my $gpgoptions ;
my %claves ;
my $replybasetemplate ;
my $from = ""  ;
my $to= "" ;
my  $subj="" ;
my  $cc=""  ;
my  $looper=""  ;

# Log function
sub lg {
	my $d= `/bin/date +"%Y-%m-%d %H:%M:%S "` ;
	chomp $d ;
	open FICHERO , ">>$logfile" ;
        print FICHERO  $d , @_ ;
	close FICHERO ;
}

sub debug {
	if ( $debug  ne 0 ) { lg "DEBUG:" , @_  } ; 
	}

sub sendmail {
        my $file=$_[0] ;
        my $to = $_[1] ;
        chomp $to ;
	debug "going to send mail to $to\n" ;
	if ($to =~ /<(.*@.*)>/ ) { $to = $1 ; }
        open FILE, $file ;
        my @tmp= <FILE> ;
        close FILE ;
        my $i= join "" , @tmp ;
        my @hostname= split /\@/, $miaddr ;
open MAIL, "| $sendmail -bs 2>/dev/null 1>/dev/null" || die ("error");

print MAIL <<EOT;
helo $hostname[1]
mail from: $miaddr
rcpt to: $to
data
$i
.

EOT
close MAIL;
        lg ("Message send to  $to\n") ;
}


sub mail_error {

	my $to = $_[0] ;
	my $codigo = $_[1] ;
	
	lg "Mail error $codigo , sending email to $to \n" ;
	my $message ;
	my @message ;
	if  (-r "$replybasetemplate.$codigo") {
		# Load a reply template
		open FILE , "$replybasetemplate.$codigo" ;
		@message = <FILE> ;
		close FILE ;
		$message = join "", @message ;
		
		#Apply simple transformation
		$message =~ s/#TO/$to/g ;
		$message =~ s/#SUBJECT/$subj/g ;
		$message =~ s/#FROM/$miaddr/g ;
		
		# Wrote the message to a file ;
		open FILE , ">$tmp3" ;
		print FILE   $message ;
		close FILE ;
		sendmail $tmp3 , $to ;
#		unlink $tmp3 ;
		}
		else {
  	  lg "Trying to use $replybasetemplate.$codigo but not found\n"; }

}

# Configuration file read
sub loadconfig {
        my $fichero= $_[0] ;
        my $linea ;
        my %return ;
        my ($cod,$val , @temp) ;
        open FILE, "$fichero" || die "Can't read the configuration file  $fichero\n" ;
        while ($linea=<FILE>) {
                next if ( $linea =~/^\n/ ) ;
                next if ( $linea =~/^#/ ) ;
                chomp $linea ;
		if ($linea  =~/.*=.*/ )  {
                @temp = split /\s*=\s*/ , $linea ;
		$cod = $temp[0] ;
                if (@temp > 2) { shift @temp ;  $val = join "=" , @temp ; }
			else  {$val = $temp[1] ; }

		$return{$cod} = $val ;
		}
		elsif  ($linea =~ /.*:.*/ ) {
		($cod, $val) = split /\s*:\s*/, $linea ;
		$claves{$cod} = $val ; 
		}
                undef $cod ;
                undef $val ;
		undef @temp ;
	}                
	close FILE ;
        return %return ;
}

sub get_config_required {
	my $key = $_[0] ;
	die "Required key $key not found in config file !!\n"  unless ( defined $config{$key} ) ;
	return $config{$key} ;
	}

# Check the keyids and try to download the not found keys from the keyserver
sub check_keys {	
	my $res ;
	foreach my $i ( keys %claves) { debug "Checking if key $i is in the keyring..\n" ;
			next if ( key_in_keyring ($i) ==0) ;
			if ( $res= import_key ($i)==0) { debug "Not in the the keyring Imported Keyid $i\n" ; }
			else {debug "error importing key $i from keyserver error code $res \n" ; }
	}
}

sub import_key {
	debug "calling import for key id $_[0]\n"  ;
	my $gpgoptions=" --no-tty  --homedir $pgpdir  --batch --yes --always-trust --recv-key $_[0] " ;
        $gpgoptions=~ /(.*)/ ;
        $gpgoptions = $1 ;
	my $re = 0xffff & system ("$gpg  $gpgoptions 2>result") ;
        debug "Execution of $gpg  $gpgoptions  results with code $re\n" ;
	return $re ;
}

sub key_in_keyring {
	my $key=$_[0] ;
	my $options="--no-tty  --homedir $pgpdir  --batch --yes --always-trust --list-keys $_[0]" ;
	debug "Checking if $key is in the public keyring ..\n" ;
        $options=~ /(.*)/ ;
        $options = $1 ;
	my $re = 0xffff & system ("$gpg  $options >/dev/null 2>/dev/null") ;
	debug "Execution of $gpg  $gpgoptions  results with code $re\n" ;
	if ($re ==0 ) { debug "key $key is in the public keyring \n" ;}
	return $re ;
}

# Return a hash with the pair keyid/email from the users of the list
sub ldap_load {
	
	my %rethash ;
	debug "Obtaining Key ids from Ldapserver. $ldapserver\n" ;
	my $ldap = Net::LDAP->new("$ldapserver" ) or die "$@";

        my $mesg = $ldap->bind ;    # an anonymous bind
	debug "Anomyous bind to ldap server done !! \n" ;

	debug "going to search with base= $ldapbase and filter=$ldapfilter\n" ;
        $mesg = $ldap->search( # perform a search
                               base   => "$ldapbase",
                                filter => "$ldapfilter"
				);

        $mesg->code && die $mesg->error ;

	debug "LDAP: Searching for list=$ldaplistname, separator is $ldapseparator field separator is $ldapfieldsep\n" ;
	$ldapseparator=~ /(.*)/ ;
	my $expr = $1 ;
	my $dat ;
        foreach my $entry ($mesg->entries) {
                          my @lineas = $entry->get_value ($ldapattribute) ;
			  foreach my $i (@lineas) {
				debug "LDAP entry: $i\n"  ;
				next unless ($i =~ $expr );
			  	($_, $dat) = split $expr , $i ;
				$ldapfieldsep =~ /(.*)/ ; 	$ldapfieldsep= $1 ; 
				my @temp = split $ldapfieldsep , $dat ;
				if ( $temp[$ldaplistpos] eq "list=$ldaplistname") {
						debug "LDAP found key $temp[$ldapkeyid] address $temp[$ldapaddress]\n" ;
						my ($k, $m) ;
						($_, $k) = split /=/ , $temp[$ldapkeyid] ;
						($_, $m) = split /=/ , $temp[$ldapaddress] ;
						$rethash{$k} = $m  ;
				}
			 	else { debug "list code is $temp[$ldaplistpos]\n" ;} 
                                
			}
	}

        $mesg = $ldap->unbind;   # take down session
	
	return (%rethash) ;
}
#  start of code

die "config file not found !!\n"  unless (defined $ARGV[0] ) ;

%config = loadconfig ($ARGV[0] ) ;
my $mimegpg=$config{'mimegpg'} ;
$pgpdir= $config{'pgpdir'} ;
$gpg=    $config{'gpg'} ;
$sendmail=$config{'sendmail'};
$sendmail =~ /(.*)/ ;
$sendmail = $1 ;
$logfile= $config{'logfile'} ;
my $user=   $config{'user'} ;
$miaddr= $config{'miaddr'} ;
my $onlymember= $config{'onlymember'} ;
my $replyon = $config{'replyon'} ;
$replybasetemplate = $config{'replybasetemplate'} ;

$debug = $config{'debug'} if (defined $config{'debug'} ) ; 
$useldap= $config{'useldap'} ;

if ($useldap == 1) {
$ldapserver =   get_config_required ('ldapserver')  ;
$ldapbase =     get_config_required ('ldapbase') ;
$ldapfilter= 	get_config_required ('ldapfilter') ;
$ldapattribute= get_config_required ('ldapattribute') ;
$ldapfieldsep= 	get_config_required ('ldapfieldsep') ; 
$ldapkeyid = 	get_config_required ('ldapkeyid') ;
$ldapaddress = 	get_config_required ('ldapaddress') ;
$ldaplistname = get_config_required ('ldaplistname') ; 
$ldaplistpos=	get_config_required ('ldaplistpos') ;
$ldapseparator=	get_config_required ('ldapseparator');
}



#
# Fixing some of the paths taint problem
$logfile=~ /(.*)/  ;
$logfile= $1 ;
$replybasetemplate =~ /(.*)/ ;
$replybasetemplate= $1 ;
$ldapserver =~ /(.*)/ ;
$ldapserver = $1 ;


lg ("Program start\n") ;

foreach my $key (keys %config) {        debug  "configuration key $key value $config{$key}\n" ; }

my @email = <STDIN> ;


lg  ("Email read\n") ;

# Check if the it is a loop due to some 
# problem, check the "X-Loop" header
my $cab = join "", @email ;
@tmp =split "\n\n", $cab ;
$cab = $tmp[0] ;
@tmp = split "\n", $cab ;
for ($i=0 ; $i!=@tmp ; $i++) {
        $looper= $1 if ($tmp[$i] =~ /^X-Loop:\s+(.*)/ ) ;
        $to  = $1 if ($tmp[$i] =~ /^To:\s+(.*)/ ) ;
        $cc  = $1 if ($tmp[$i] =~ /^Cc:\s+(.*)/ ) ;
        $subj= $1 if ($tmp[$i] =~ /^Subject:\s+(.*)/ ) ;
        $from= $1 if ($tmp[$i] =~ /^From:\s+(.*)/ ) ;
}
chomp $to if ($to ne "") ;
chomp $cc if  (($cc ne "") && (defined $cc)) ;
chomp $subj  if ($subj ne "");
chomp $from if ($from ne "");
lg ("Message received from  $from\n") ;

if ($looper =~ /$miaddr/ ) {
                lg ("Loop email from  $from , subject  $subj\n");
                exit (0) ;
		}
elsif ($from =~/$miaddr/ ) {
               lg ("Loop email recived from list address  $from \n");
                exit (0) ;
		}
elsif ($from =~ /mailer-daemon@/i)  {
        	lg ("Mailer daemon error from   $from , subject $subj\n");
        	exit (0) ;
	}


# Decrypt the message


open  FICHERO, ">$tmp1" || die "I can't write the email \n" ;

for ($i=0 ; $i< @email ; $i++ ) { print FICHERO $email[$i] ;}
close FICHERO ;
debug ("Fichero temporal $tmp1 con el correo recibido\n") ;

$ENV{'PATH'} = '' ;

$gpgoptions = "--homedir $pgpdir  -u $user " ;
#
# Fixing gpgoptions and gpg taint problem 
# (we can trust in our configuration file ;-)
$gpg =~ /(.*)/ ;
$gpg=$1 ;
$gpgoptions=~ /(.*)/ ;
$gpgoptions= $1 ;

$re = 0xffff & system ("$gpg  $gpgoptions < $tmp1 > $tmp2 2>$tmp5") ;
debug "Ejecutado: $gpg  $gpgoptions < $tmp1 > $tmp2 2>$tmp5\n" ;


if (!$debug) { 	unlink $tmp1 ; }
	else {
		debug "debug mode $tmp1 not deleted (encrypted mail received)\n" ; }


if ($re !=0 ) {
	debug "Result of execution of gpg is $re\n" ; 
	# some problem with the ggp some values:
	# 512: message not encrypted
	lg ("Message not encrypted or encrytation key not valid\n") ;
	unlink $tmp2 ; unlink $tmp5 ;
	if ($replyon =~ /notencrypted/i ) {
		mail_error ($from ,'NOTENCRYPTED' ) ;		
	exit (0) ;
	}
} else { debug "successfully decrypted message \n" ;  }

#
# Check if the message was correctly signed by any key of the list
my $goodsig="" ;
my $signer="" ;

open F , "$tmp5" ;
while ($i = <F> ) {
	if ($i =~/Good signature from/ ) { $goodsig=1 ; }
	elsif ($i =~ /Signature made .*using .*key ID (.*)/)
			{$signer="0x$1" ; }
}
debug "Email signed by keyid $signer (good signature = $goodsig) \n" ; 

if ($goodsig != "1" ) {
	lg "Error , with the email signature. Signature made by   $signer not valid\n" ;
	if ($replyon =~ /badsignature/i ) {
		mail_error ($from ,'BADSIGNATURE' ) ; }		
	exit (0) ;}
	 
if ( !(defined $claves{$signer}) && ($onlymember=="1")) {
   lg ("Error Key $signer is not a member of the restricted list (only member on)");
	if ($replyon =~ /onlymember/i ) {
		mail_error ($from ,'ONLYMEMBER' ) ;		
	exit (0) ; }
}

close F ;
unlink $tmp5 ;

# Send the encrypted email to the members of the list

if ($useldap == 1 ) {
	# Load the keyid definition from LDAP 
	# Add the keys to the gpg keyring
	%claves = ldap_load() ;
	}

check_keys ;


if ($debug ) { 	foreach my $k (keys %claves) { debug "Key member $k with mail address $claves{$k}\n" ; } }

foreach $i (keys %claves) {
	debug "Going to encrypt for $i....\n" ;
	$gpgoptions=" -seat --batch -v --no-tty --debug-all --homedir $pgpdir  --batch --yes --always-trust -u $user -r $user -r $i" ;
	$gpgoptions=~ /(.*)/ ;
	$gpgoptions = $1 ;
	$re = 0xffff & system ("$gpg  $gpgoptions < $tmp2 > $tmp4 2>result") ;
	debug "Execution of $gpg  $gpgoptions < $tmp2 > $tmp4 2>/dev/null results with code $re\n" ;
	lg "Encrypting email for Keyid $i address $claves{$i}\n" ;

# New mail 
if ($replyon =~/success/ ) {
	mail_error ($from , 'SUCCESS' ) ;
	}

my $boundary="=_encripted-message-" . time  ;

my $encrypt ;

my $cabecera=<<EOF;
Content-Type: multipart/encrypted;
    boundary="$boundary";
    protocol="application/pgp-encrypted"

This is a MIME GnuPG-encrypted message.  If you see this text, it means
that your E-mail or Usenet software does not support MIME encrypted messages.

--$boundary
Content-Type: application/pgp-encrypted
Content-Transfer-Encoding: 7bit

Version: 1

--$boundary
Content-Type: application/octet-stream
Content-Transfer-Encoding: 7bit

EOF

my $pie=<<EOF;

--$boundary--
EOF

	
open FICHERO, ">$tmp3" || die "I can't write in temporal file $tmp3 \n" ;

($j, $_)= split /\n\n/ , join "", @email  ;

@tmp= split /\n/, $j ;
for ($j =0 ; $j < @tmp ; $j ++ ) {
	next if $tmp[$j] =~ /^Content-Type:/ ;
	next if $tmp[$j] =~ /^\s*boundary=/ ;
	next if $tmp[$j] =~ /^\s*protocol=/ ;
	next if $tmp[$j] =~ /^Content-Transfer-Encoding:/ ;
	print FICHERO "$tmp[$j]\n" ;
}

open FICHERO2, "$tmp4" ; 
print FICHERO  $cabecera ;
while ($j=<FICHERO2>) { print FICHERO $j ; }
close FICHERO2 ;
print FICHERO  $pie ;
close FICHERO ;

sendmail ($tmp3 , $claves{$i} ) ;
unlink $tmp4 , $tmp3 ;
	
}

#  remove last file
unlink $tmp5 ;

