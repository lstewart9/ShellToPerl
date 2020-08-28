#!/usr/bin/perl -w	

use strict;


my @input = <>;
my @output = @input;

foreach my $line (@output) {
	#semi-colon indicator
	my $sc = "true";
	#new-line indicator
	my $nl = "true";
	my $converted = "false";
	my $comment = "";

	if ($line =~ s/^#!\/bin\/dash$/#!\/usr\/bin\/perl -w/ or $line =~ /^$/ or $line =~ /^\s*#/) {
		next;
	}

	#takeaway end of line comments and add on at the end
	if ($line =~ /[^\$]#[^'"]*$/) {
		$line =~ s/^(.*[^\$\s])(\s*#[^'"]*)$/$1/;
		$comment = $2;
	}

	($line, $converted) = convert_variables($line, $converted);
	($line, $converted) = convert_assign_variables($line, $converted);	
	($line, $converted) = convert_cd($line, $converted);	
	($line, $converted) = convert_read($line, $converted);		
	($line, $converted) = convert_exit($line, $converted);	

	($line, $converted) = convert_brackets($line, $converted);
	($line, $converted) = convert_dollardoubleparen($line, $converted);
	($line, $converted) = convert_test($line, $converted);	


	($line, $converted, $sc) = convert_for_and_while_loop($line, $converted, $sc);
	($line, $converted, $sc) = convert_if_statement($line, $converted, $sc);

	($line, $converted) = convert_backtick($line, $converted);	
	#echo conversions uses $() for backtick so convert $() after echo conversion
	($line, $converted, $nl) = convert_echo($line, $converted, $nl);
	($line, $converted) = convert_dollarparen($line, $converted);

	($line, $converted) = convert_expr($line, $converted);	

	if ($converted eq "false") {
		#if not seen, assume it is a system call
		$line = convert_system($line);
	} elsif ("$line" eq "\n") {
		#converted is true
		#remove empty line which has been created by conversion e.g. due to removal of "then"
		$line =~ tr/\n//d;
	}

	#add semicolon to line if needed
	if ($sc eq "true") {
		chomp $line;
		#put back comments at the end of a line if necessary
		if ("$comment" ne "") {
			$line = $line.";".$comment;	
		} else {
			$line = $line.";\n";	
		}
	} else {
		#commend by no semicolon
		if ("$comment" ne "") {
			chomp $line;
			$line = $line.$comment;
		}
	}
}

print @output;

if ($output[$#output] eq "}") {
	print "\n";
}

sub convert_echo {
	my ($line, $converted) = @_;
	
	if ($line =~ /^\s*echo/){
		$converted = "true";

		
		#check if -n option used
		my $addnl = '."\\n"';
		if ($line =~ /^\s*echo\s+-n /){
			$addnl = "";
			$line =~ s/^(\s*echo\s+)\-n /$1/;
		}


		#if variables in '' put \ in front so they are not expanded
		$line =~ s/'(.*)\$(.*)'/$1\\\$$2/g;

		
		
		#remove all '' which are not enclosed in "" and vice versa
		#use | as a temp to store '
		$line =~ s/^([^"]*)'(.*)'([^"]*)$/$1|$2|$3/g;
		$line =~ s/^([^|]*)"(.*)"([^|]*)$/$1$2$3/g;
		#place will have to put \ in front of " that are withing ''
		
		$line =~ tr/|//d;
		$line =~ s/"/\\"/g;

		$line =~ s/echo (.*)/print "$1"$addnl/;
		
		#should these be global sed
		#remove scalar(@ARGV) from quotes
		if ($line =~ /scalar(@ARGV)/) {
			#if middle of echo
			$line =~ s/("[^"]+)scalar\(\@ARGV\)([^"]+")/$1"\.scalar(\@ARGV)\."$2/g;
			#if beginning of echo
			$line =~ s/"scalar\(\@ARGV\)([^"]+")/scalar(\@ARGV)\."$1/g;
			#if end of echo
			$line =~ s/("[^"]+)scalar\(\@ARGV\)"/$1"\.scalar(\@ARGV)/g;
			#if by itself
			$line =~ s/"scalar\(\@ARGV\)"/scalar(\@ARGV)/g;
		}

		#remove $() from quotes 
		if ($line =~ /\$\((.*)\)/) {
			#if command not recognised use system
			my $command = $1;
			if (not $command =~ /^(?:cd|exit|read|cd|test|expr) / and not $command =~ /[-\/+\/\*]/) {
				$line =~ s/\$\((.*)\)/\$(system "$1")/;
			}	
			#if middle of echo
			$line =~ s/("[^"]+)\$\((.*)\)([^"]+")/$1",$2,"$3/g;
			#if beginning of echo
			$line =~ s/"\$\((.*)\)([^"]+")/$1,"$2/g;
			#if end of echo
			$line =~ s/("[^"]+)\$\((.*)\)"\./$1",$2,/g;
			#if by itself
			$line =~ s/"\$\((.*)\)"\./$1,/g;
		}

	}
	return ($line, $converted);
}

sub convert_variables {
	my ($line, $converted) = @_;
	#convert variables if lines does not have ' before it.
	if ($line =~ /^(\s*)[^']*\$\S+/) {
		my $indent = $1;
		#go through word by word
		my @words = split " ", $line;
		foreach my $word (@words) {
			if ($word =~ /'.*'/) {
				next;
			}
			if ($word =~ /\$([\d]+)/) {
				my $index = $1;
				if ($index != 0) {
					$index--;
					$word =~ s/\$[\d]+/\$ARGV\[$index\]/g;
				} else {
					#$0 in shell is the file name which = $0 in perl
					#don't have to handle this
					$word =~ s/\$[\d]+/\$$index/g;
				}
				
			}
			#convert $#
			$word =~ s/\$#/scalar(\@ARGV)/g;
			#convert $*
			$word =~ s/\$\*/\@ARGV/g;
			#convert $@
			if ($word =~ s/"\$\@"/\@ARGV/g) {}
			else {
					$word =~ s/\$\@/\@ARGV/g;
			}
		}
		$line = join " ", @words;
		$line = $indent.$line."\n";
	}
	return ($line, $converted);
}

sub convert_assign_variables {
	my ($line, $converted) = @_;
	#create test assigning a variable to another variable

	#insert $() and `` stuff here i quess
	if ($line =~ /^(\s)*[\d\w_]+=/) {
		$converted = "true";
		if ($line =~ s/(\s*)([\d\w_]+)="(\$\(.*\))"/$1\$$2 = $3/){}
		elsif ($line =~ s/(\s*)([\d\w_]+)=(["'])(.*)(["'])/$1\$$2 = $3$4$5/){}
		elsif ($line =~ s/(\s*)([\d\w_]+)=(.*\$.*)/$1\$$2 = $3/) {}
		else {
			#if no quations and assigning to variable, dont use ""
			$line =~ s/(\s*)([\d\w_]+)=(.*)/$1\$$2 = "$3"/
		} 
	}
	return ($line, $converted);
}

sub convert_cd {
	my ($line, $converted) = @_;
	#create test assigning a variable to another variable
	if($line =~ /^\s*cd /) {
		$converted = "true";
		if ($line =~ s/(\s*)cd (["'])(.*)(["'])/$1chdir $2$3$4/){}
		else {
			#if no quations defualt to ""
			$line =~ s/(\s*)cd (.*)/$1chdir "$2"/
		} 
	}
	return ($line, $converted);
}

sub convert_exit {
	my ($line, $converted) = @_;
	if($line =~ /^(\s*)exit /) {
		#do nothing
		$converted = "true";
	}
	return ($line, $converted);
}

sub convert_read {
	my ($line, $converted) = @_;

	if($line =~ /^\s*read /) {
		$converted = "true";
		$line =~ s/(\s*)read ["']?(.*)["']?/$1\$$2 = <STDIN>;\n$1chomp \$$2/;	
	}
	return ($line, $converted);
}

sub convert_for_and_while_loop {
	my ($line, $converted, $sc) = @_;

	if($line =~ /^\s*for / or $line =~ /^\s*while / or$line =~ /^\s*do$/ or $line =~ /^\s*done$/) {
		$converted = "true";
		$sc = "false";
		if ($line =~ /^\s*for [\w\d_]+ in (.*)/) {
			#for loop
			my @elements = split ' ', $1;
			if (@elements == 1) {
				#check if regex file match, if not treat as file name
				my $element = $1;
				if ($element =~ /[\?\*\[\]]/) {
					$elements[0] = "glob(\"$element\")";
				}
			} else {
				foreach my $element (@elements) {
					$element = "'$element'";
				}
			}
			my $elements = join ', ', @elements;
			$line =~ s/^(\s*)for ([\w\d_]+) in .*/$1foreach \$$2 ($elements) \{/;
		} elsif ($line =~ /^\s*while /) {
			#while loop
			if ($line =~ s/(^\s*)while true/$1while (1) \{/){}
			else {
				$line =~ s/(^\s*)while (.*)/$1while ($2) \{/;	
			}
			
		}
		$line =~ s/^\s*do$//;
		$line =~ s/^(\s*)done$/$1\}/;

	}
	return ($line, $converted, $sc);
}

sub convert_if_statement {
	my ($line, $converted, $sc) = @_;

	if ($line =~ /^\s*if / or $line =~ /^\s*then$/ or $line =~ /^\s*fi$/ or $line=~ /^\s*elif/ or $line=~ /^\s*else$/){
		$converted = "true";
		$sc = "false";

		$line =~ s/^(\s*)if (.*)/$1if ($2) \{/;
		$line =~ s/^(\s*)elif (.*)/$1\} elsif ($2) \{/;
		$line =~ s/^(\s*)else$/$1\} else \{/;
		$line =~ s/^(\s*)fi$/$1\}/;
		$line =~ s/^\s*then$//;
	} 
	return ($line, $converted, $sc);
}

sub convert_test {
	my ($line, $converted) = @_;

	if ($line =~ /^[^"']*test / ) {
		$converted = "true";

		
		if ($line =~ s/^([^"']*)test -(\w+) (["'])(.*)(["'])/$1-$2 $3$4$5/) {}
		else {
			#if no quotations defualt to ""
			($line =~ s/^([^"']*)test -(\w+) (.*)/$1-$2 "$3"/);
		}

	
		$line =~ s/^([^"']*)test (["'])(.*)(["']) = (["']?)(.*)(["']?)/$1$2$3$4 eq $5$6$7/;
		$line =~ s/^([^"']*)test (["'])(.*)(["']) != (["']?)(.*)(["']?)/$1$2$3$4 ne $5$6$7/;
		$line =~ s/^([^"']*)test (.*) = (.*)/$1"$2" eq "$3"/;
		$line =~ s/^([^"']*)test (.*) != (.*)/$1"$2" ne "$3"/;
		
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -lt (["']?)(.*)(["']?)/$1$2$3$4 < $5$6$7/;
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -gt (["']?)(.*)(["']?)/$1$2$3$4 > $5$6$7/;
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -eq (["']?)(.*)(["']?)/$1$2$3$4 == $5$6$7/;
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -le (["']?)(.*)(["']?)/$1$2$3$4 <= $5$6$7/;
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -ge (["']?)(.*)(["']?)/$1$2$3$4 >= $5$6$7/;
		$line =~ s/^([^"']*)test (["']?)(.*)(["']?) -ne (["']?)(.*)(["']?)/$1$2$3$4 != $5$6$7/;

		#remove "" around scalar(@ARGV)
		$line =~ s/"scalar\(\@ARGV\)"/scalar(\@ARGV)/;
	
	}
	return ($line, $converted);
}

sub convert_expr {
	my ($line, $converted) = @_;

	if ($line =~ /^[^']*expr /) {
		$converted = "true";
		#convert /* to * for multiplication
		$line =~ s/^([^']*)expr (.*) \\\* (.*)/$1$2 \* $3/g;
		$line =~ s/^([^']*)expr (.*)/$1$2/g;
		
	}
	return ($line, $converted);

}

sub convert_backtick {
	my ($line, $converted) = @_;
	if($line =~ /^[^']*`.*`/) {
		$line =~ s/^([^']*)`(.*)`/$1\$($2)/;
	}
	return ($line, $converted);
}

sub convert_dollarparen {
	my ($line, $converted) = @_;
	
	if($line =~ /^[^']*\$\((.*)\)/) {
		
		my $command = $1;
		#if command not recognised use system
		if ($command =~ /^expr/) {
			$line =~ s/^([^']*)\$\((.*)\)/$1$2/;
		} else {
			$line =~ s/^(\s*)([^']*)\$\((.*)\)/$1chomp($2`$3`)/;
		}
	}
	return ($line, $converted);
}

sub convert_brackets {
	my ($line, $converted) = @_;
	if($line =~ /^[^']*\[ .*\ ]/) {
		$line =~ s/^([^']*)\[ (.*)\ ]/$1test $2/;
	}
	return ($line, $converted);
}

sub convert_dollardoubleparen {
	my ($line, $converted) = @_;

	if($line =~ /^[^']*\$\(\(.*\)\)/) {
		$line =~ s/^([^']*)\$\(\(\s*(.*)\s*\)\)/$1\$(expr $2)/;
	}
	return ($line, $converted);
}

sub convert_system {
	my ($line, $converted) = @_;

	if ($line =~ s/^(\s*)(["'])(.*)(["'])/system $1$2$3$4/){}
	else {
		#if not qutation defualt to ""
		$line =~ s/^(\s*)(.*)/$1system "$2"/;
	}
	
	
	return $line;
}
