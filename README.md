
$Id: readme,v 1.4 2006/11/21 18:09:53 paco Exp $

 PGP encrypted mail aliases

Description.
-----------

 This is a small script to provide PGP/MIME encrypted mailing lists aliases. The
script allow to setup small mailing lists in which all the emails (incoming and
outgoing are PGP/Mime encrypted).

 The script provides the following anti-spam features:

 - Only PGP encrypted mails to the mailing list address will be accepted.
 - Option to allow also posting only from members of the lists or from everyone
 that knows the public key of the mailing list.
 
  The PGP private key of the list must not be password protected in the
server , so the list should be installed in a proctected/trusted machine.


Configuration file.
-------------------


 The script is launched from the /etc/aliases, and received a configuration
file as argument, for example:

 pruebas: 	"|/usr/local/bin/gpg-aliases.pl /usr/local/lists/mail-example.list"

 the configuration file is an ASCII configuration file with four types of lines:
+ Comments and newlines: Lines that start with "#" are ignored
+ Configuration option: separated by "=", (variable, values), the following
variables should be set:

  - pgpdir : Directory in which the keyring will be stored.
  - gpg: Path to the gpg binary
  - sendmail: Path to the sendmail binary
  - logfile: Path to file in which it will be stored the logs
  - onlymember: set to 1 if you wan to only allow posts from keys (not address) in
    the member list, if not set everyone with access to the public key of the
    list can post an encrypted mail to the list.
  - user: userid or keyid of the key of the list, used to know to which key you should
    encrypt the mail.
  - miaddr: email address of the aliases, to avoid bounce mails.

  - replyon: when the mailing list should reply with a message to the 
user , accepted values are: notencrypted, onlymember, badsignature, and
success , meaning that the list address should be respond to the mail when:
 + notencrypted: Message is not encrypted to the list PGP key.
 + onlymember: Message is encrypted, but only member of the list can post.
 + badsignature: bad signature of the message.
 + success: Message accepted and redistributed to the list.
   If this value is set, the next parameter should be also be set.

  - replybasetemplate : base path of the reply messages, the path
is build with the replybasetemplate and the suffix: "NOTENCRYPTED",
"BADSIGNATURE", "ONLYMEMBER" , "SUCCESS.

 Example: If you set replyon to reply on notencrypted messages, and
 you set:
	replyon = "notencrypted"
	replybasetemplate ="/usr/local/lists/pruebas/reply " ;
	
 And you should also create the file /usr/local/lists/pruebas/reply.NONENCRYPTED

 In the template the following keywords can be used to replace values of
the original mail:

 -#TO: Sender of the message (from)
 -#SUBJECT: Subject of the message
 -#FROM: Address of the list aliases

  - norepro .  do the mail must be redistriduted to the sender ?, in normal
use the mail is send to all list keys/mailaddress but setting this flag
to "1" says that mail will not be redistributed to the sender. This could be
used with automatic tools to redistribute files and avoid flooding .

(* NEW OPTIONS:
 -  useldap, if set to 1, it will retrieve list members information from ldap, instead of the
  old notation below).
 - ldapserver: Address of the ldap server, it should be in the notation ldap://host:port , for
 example  ldapserver=ldap://ldap.rediris.es:1389

 - ldapbase , base of the ldap seaarch, for example ldapbase=dc=rediris,dc=es
 - ldapfilter, filter used in the search, must be a complete ldap filter, for example:
ldapfilter=(irisUserEntitlement=*pgp*list=tecniris*)

 - ldapattribute: Attribute used for storing the list information in  the ldap objects, for example:
    ldapattribute=irisUserEntitlement
 - ldapseparator: code used to separate the in the attribute the pgp related information 
	ldapseparator=:pgp:
 - ldapfieldsep , is the character used as field separatator ldapfieldsep=; there are three other values used:
 -  ldapekyid the possition  in which the keyid information is, format perl array (first element is 0) ej. ldapkeyid=0
 -  ldapaddress , possition in which the mail address s, ejldapaddress=2
 - ldaplistpos, possition of the mailing list , ej ldaplistpos=1 
 -  ldaplistname. name of the list in ldap.  ldaplistname=pruebas

 Example:
 
 We at rediris, use the attribute "irisUserEntitlement" to store personal information about some thing like the keyids,
 the format of one of this entitlement is :

   urn:mace:rediris.es:entitlement:pgp:keyid=0xD3A42C61;list=tecniris;mail=francisco.monserrat@rediris.es
 (see at mace.rediris.es for more information )
 
 in order to search in the directory, we define:
  ldapattribue: iriUserIntitlement 
  ldapsepseparator: ":pgp:" , the script will allways take the part in the left of the split ...
  ldapfieldsep: The script will separate using ";" as separator, so we will have and
 array with:
   0 = keyid=0xD3A42C61  (ldapkeyid)
   1 = list=tecniris     (ldaplistpos)
   2 = mail=francisco.monserrat@rediris.es (ldapaddress)

 As an user can be member of several mailing list, we check if "list=ldaplistname" , also to be multilingual, the name of the
attributes (keyid, mail, etc) don't matter we split again using "=" and keep the right part.

*)




  - list of members of the list, keyid & email address to send the mail to,
separated by a semicolon ":" , you must add manually the keys to the public
ring.


How to setup an encrypted mailing lists
---------------------------------------

 steps:

1. Create a directory to store the PGP keys, (variable pgpdir in the configuration file)
 for example /usr/local/etc/lists/mail-example

2. Change to this directory and using gpg generate a new key pair 
to the lists (use the --homedir option with gpg to define the 
path to the keyrings. example:
 gpg --homedir /usr/local/etc/lists/mail-example --gen-key 


3. Add the public keys to the ring (against with --homedir option)
  gpg --homedir /usr/local/etc/lists/mail-example --keyserver your.favorite.keyserver --search-key user1  

4. Modify the configuracion.example file to add the members of the
lists and the different options, and place it in a directory
(for example /usr/local/etc/lists )


5. change the uid of the files in the pgpdir to the user and group
of the user that runs the /etc/aliases mails (nobody in postfix).

6. Modify the /etc/aliases file to launch the scripts:
 mail-example: |/usr/local/bin/mail-gpg /usr/local/etc/lists/mail-example.list
(and rebuild the aliasdb with newaliases)

7. export the public key of the list 
   gpg --homedir /usr/local/etc/lists/mail-example --export -a miaddr > file
 and distribute it to the list members.

8 Test it with an email to the mailing list address


Notes
-----

1. As stated before the identification of the user (posters) to the list is
based in the PGP keys not the mail address.

2. The mail is sent to the mail address listed in the configuration file ,
encrypted with the keyid, there is no verification that the keyid/email address
is correct.

3. The keyrings can be shared by different lists in the server but it is better
to keep the keyring separated for each list.

4. Speed in a not heavy loaded PIII 800Mz is about 5segs for each member of the
list.

5. Source code and information at, http://www.rediris.es/app/pgplist/

