use strict;
use warnings;
use Data::Dumper;
use List::MoreUtils 'all';
use Scalar::Util;
use List::Flatten::Recursive;
#use JSON::PP;

package JunosCFG::Cfg;

sub __debug { my $s=shift; return ( defined($s->{opts}{DebugFunc}) ? $s->{opts}{DebugFunc}(__PACKAGE__, @_) : 0 ); }

sub new($$) {
    my ($class, $opts) = (@_);
    my $self = {opts => $opts};

    # new structure
    $self->{cfg} = (ref($opts->{cfg}) eq 'HASH' ? $opts->{cfg} : {});
    # old structure
    $self->{c} = {'__name' => '__root'};

    bless $self, $class;

#    $self->{name} = $_name;

    return $self;
}

sub __index($$) {
    my ($_hsh, $_key) = (@_);
    if(ref($_hsh) ne 'HASH') {
	die __PACKAGE__.':'.__LINE__.'->__index('.Data::Dumper::Dumper($_hsh).', '.$_key.') ERROR: ref(_hsh) ne HASH!';    
    }
    $_hsh->{'__idx'} = {} if ref($_hsh->{'__idx'}) ne 'HASH';
    if(!defined($_hsh->{'__idx'}{$_key})) {
	push(@{$_hsh->{'__order'}}, $_key);
	$_hsh->{'__idx'}{$_key} = scalar(@{$_hsh->{'__order'}})-1;
    }
    
    return(1);
}

sub __assignOrderedItem($$$;$) {
    my ($self, $_hsh, $_key, $_val,$__unique) = (@_);

    __index($_hsh, $_key);
    
    my $unique = (defined($__unique) && $__unique == 1 ? 1 : 0);
    
    if(!$unique && defined($_hsh->{$_key}) && ref($_hsh->{$_key}) ne 'ARRAY') {
	my $_tmp = $_hsh->{$_key};
	$_hsh->{$_key} = [];
	push(@{$_hsh->{$_key}}, $_tmp);
    }
    
    if(ref($_hsh->{$_key}) eq 'ARRAY') {
	push(@{$_hsh->{$_key}}, $_val);
    }
    else {
	$_hsh->{$_key} = $_val;
    }
}

sub __assignAtCurrentDepth($$$$) {
    my ($self, $__currentDepths, $__key, $__val) = (@_);
    my $_locatorStr = 
	join(' ', map { $__currentDepths->{$_} } sort {$a <=> $b} keys %{$__currentDepths});
#    my $_leafNode = $self->__locateLeafNode($self->{cfg}, $_locatorStr);
    my $_leafNode = $self->__locateLeafNode($_locatorStr);

    return ( $self->__assignOrderedItem($_leafNode, $__key, $__val) );
}

sub __quotedWhitespaces($) {
    $_ = shift(@_);
    for(;;) {
	my $_o = $_;
	$_ =~ s/("[^\s]+)\s+([^"]+")/${1}\\s${2}/goi;
	last if $_o eq $_;
    }
    $_ =~ s/"//go;
    return $_;			
}

sub __locateLeafNode($$;$) {
    my ($self, $__locatorStr, $__treePtr) = (@_);
    #        my ($self, $__treePtr, $__locatorStr) = (@_);

    die '__locateLeafNode: Invalid __locatorStr = '.$__locatorStr if $__locatorStr =~ /\s\s/;
    
    my $_returnPtr = (ref($__treePtr) eq 'HASH' ? $__treePtr : $self->{cfg});
    
    my $_locatorStr = __quotedWhitespaces($__locatorStr);

    foreach my $_leafNode (split(/\s/o, $_locatorStr)) {
	$_leafNode =~ s/\\s/ /go;

	die '_returnPtr<'.ref($_returnPtr).'> ne HASH @ '.$_locatorStr.' Dump: '.Data::Dumper::Dumper($__treePtr) if(ref($_returnPtr) ne 'HASH');
	
	if(ref($_returnPtr->{$_leafNode}) ne 'HASH') {
	    my $_newLeafNode = {};

	    $self->__assignOrderedItem($_returnPtr, $_leafNode, $_newLeafNode);
	}

	$_returnPtr = $_returnPtr->{$_leafNode};
    }
    return $_returnPtr;
}

sub __generatePad($) {
    my $_depth = shift;
    my $_padTpl = " " x 4;
    return ($_padTpl x ($_depth - 1));
}

sub __generatePadsDown($$;$) {
    my ($__from, $__to, $debug) = (@_);
    my $_str = '';
    my $_padTpl = " " x 4;
    
    $debug = (defined($debug) && $debug == 1 ? 1 : 0);
    for(my $_d=$__from;$__to<=$_d;$_d--) {
	my $_pad = ($_padTpl x ($_d - 1));
	my $_debugStr = join(' ', ' # ', '['.$_d.'] Pad:',bytes::length($_pad), '__generatePadsDown('.$__from.','.$__to.')');
	$_str .= $_pad."}".($debug==1 ? $_debugStr : '')."\n";
    }
    return $_str;
}

sub __resolveAttribute($$) {
    my ($_resolver, $_attr) = (@_);
    $_attr = lc($_attr);
    return (defined($_resolver->{$_attr}) ? $_resolver->{$_attr} : '@@UNRESOLVED-ATTRIBUTE:'.$_attr.'@@');
}

sub __translateDataKey($$) {
    my ($__ptr, $_locator) = (@_);
    my $_return;
    my $_ptr = $__ptr;
    
    my @_dataParts = split(':', $_locator);
    my $_keyItem = pop(@_dataParts);

    
    foreach my $_k (@_dataParts) {	
	my $_keyHsh = lc($_k);

#	print "Trying ".$_k." / ".$_keyHsh."\n";
	my $_lc = {};
	%{$_lc} = map { lc($_) => $_; } keys %{$_ptr};

#	if(defined($_lc->{$_keyHsh}) && ref($_ptr->{$_lc->{$_keyHsh}}) eq 'HASH') {
	if(defined($_lc->{$_keyHsh})) {
#	    print "found\n";
	    $_ptr = $_ptr->{$_lc->{$_keyHsh}};
	}
	else {	    
	    $_ptr = undef;
	    last;
	}
    }

    my $_lcPtr = {};
    %{$_lcPtr} = map { lc($_) => $_; } keys %{$_ptr} if ref($_ptr) eq 'HASH';
    
    if(ref($_ptr) eq 'HASH' && defined($_lcPtr->{$_keyItem})) {
	$_return = $_ptr->{$_lcPtr->{$_keyItem}};
    }
    elsif(defined($_ptr) && ref($_ptr) ne 'HASH') {
	$_return = $_ptr;
    }

    if(!defined($_return)) {
#	print "RAW Key<".$_keyItem."> was: ".$_locator." PTR was at ".Data::Dumper::Dumper($_ptr)." and keyItem was: ".$_keyItem." Original PTR: ".$__ptr."\n";
#	<STDIN>;
    }
    
    #    @@UNRESOLVED-DATA:Base:Credential:root@@
    
    return $_return;
}

sub __resolveData($$) {
    my ($_resolver, $_dataKey) = (@_);

    my $_return = __translateDataKey($_resolver, $_dataKey);

    return (defined($_return) ? $_return : '@@UNRESOLVED-DATA:'.$_dataKey.'@@');
}

sub __renderItem($$) {
    my ($__data, $__item) = (@_);
    return undef if !defined($__item);
    my $_return = $__item;
#    my $_attrs = $__data->{'Attr'}{$__nodeName};
    my $_attrs = $__data->{'Attr'};
    my $_data = $__data->{'Data'};

    $_return =~ s/\@\@{A:([A-Z0-9\-:_\.]+)}\@\@/__resolveAttribute($_attrs, $1);/goie;

    $_return =~ s/\@\@{D:([A-Z0-9\-:_\.]+)}\@\@/__resolveData($_data, $1);/goie;
    
    return $_return;		
}

sub __orderedTree($$;$$) {
    my ($self, $__tree, $__data, $_templateFormat) = (@_);

    my $_return = [];
    my $_orderedItems = [[0, $__tree, 'root', $_return]];

    for(;;) {
	last if scalar(@{$_orderedItems})==0;
	#       print "OrderedItems[]/pre = ".join(@{$_orderedItems});
	my $_oItems;
	@{$_oItems} = @{$_orderedItems};

	$_orderedItems = [];
	
	for(;my $_oItem = shift(@{$_oItems});) {
	    
	    my ($_depth, $_cItem, $_cName, $_pOut) = ($_oItem->[0], $_oItem->[1], $_oItem->[2], $_oItem->[3]);
	    if(ref($_cItem->{'__order'}) eq 'ARRAY') {
		map {
		    my $_item = $_;
		    my $_rendered = ($_templateFormat == 1 ? $_item : __renderItem($__data, $_item));

		    if(ref($_cItem->{$_item}) eq 'HASH') {
			my $_newPout = [];
#			push(@{$_pOut}, [$_depth+1, 'LEAF', __renderItem($__data, $_item), $_newPout]);
			push(@{$_pOut}, [$_depth+1, 'LEAF', $_rendered, $_newPout]);
			push(@{$_orderedItems}, [$_depth+1, $_cItem->{$_item}, $_item, $_newPout]);
		    }
		    elsif(ref($_cItem->{$_item}) eq 'ARRAY') {
			for(my $_x = 0;$_x<=(scalar(@{$_cItem->{$_item}})-1);$_x++) {
#			    push(@{$_pOut}, [$_depth, 'KEYVAL', __renderItem($__data, $_item),
			    #					     __renderItem($__data, $_cItem->{$_item}[$_x])]);
			    my $_renderedX = ($_templateFormat == 1 ? $_cItem->{$_item}[$_x] : __renderItem($__data, $_cItem->{$_item}[$_x]));;
			    push(@{$_pOut}, [$_depth, 'KEYVAL', $_rendered, $_renderedX]);
			}
		    }
		    else {
#			push(@{$_pOut}, [$_depth, 'KEYVAL', __renderItem($__data, $_item),
			#					 __renderItem($__data, $_cItem->{$_item})]);
			my $_renderedX = ($_templateFormat == 1 ? $_cItem->{$_item} : __renderItem($__data, $_cItem->{$_item}));
			push(@{$_pOut}, [$_depth, 'KEYVAL', $_rendered, $_renderedX]);
			
		    }
		} @{$_cItem->{'__order'}};
	    }
	    else {
		my $_rendered = ($_templateFormat == 1 ? $_cName : __renderItem($__data, $_cName));
#		push(@{$_pOut}, [$_depth, 'LEAF-EMPTY', __renderItem($__data, $_cName), undef]);
		push(@{$_pOut}, [$_depth, 'LEAF-EMPTY', $_rendered, undef]);
		next;
	    }
	}
    }

    return $_return;
}

# MUST be used with non-OLD
sub format($$$;$) {
    my ($self, $fmt, $__renderData, $_templateFormat) = (@_);

    $_templateFormat = (defined($_templateFormat) &&  $_templateFormat == 1 ? 1 : 0);
    
    $fmt = (defined($fmt) && $fmt =~ /^(set)$/oi ? lc($fmt) : 'ascii');

#    return JSON::PP::encode_json($self->{cfg}) if $fmt eq 'json';
    
    my $_orderedTree = $self->__orderedTree($self->{cfg}, $__renderData, $_templateFormat);

    my @flattened = List::Flatten::Recursive::flat($_orderedTree, $__renderData);

    my $_currentDepth = 0;
    my $_currentLeafLength = {};
    my $_previousType = '';
    my $_configTxt = '';

    my $_depthInfo = {};
    my $_prevType;   
 
    for(my $_x=0;$_x<=(scalar(@flattened)-1);$_x++) {
	my $_shift = 2;
	my $_depth = $flattened[$_x];
	my $_type  = $flattened[$_x+1];
	my $_name = $flattened[$_x+2];
	my $_val = '';

	last if !defined($_type);

	if($_depth < $_currentDepth) {
	    map { delete $_depthInfo->{$_} if $_ > $_depth; } keys %{$_depthInfo};
	}
	
	if($_type eq 'KEYVAL' || $_type eq 'LEAF-EMPTY') {
	    $_val = $flattened[$_x+3];
	    $_val =~ s/\n//go if defined($_val);
	    $_shift++;
	}

	if($_type eq 'KEYVAL') {

	    my $comment;

	    my $_secretRe = qr{^(secret|encrypted|md5)};
	    
	    if((defined($_val) && $_val =~ $_secretRe) ||
	       (defined($_name) && $_name =~ $_secretRe)) {
		$comment .= 'SECRET-DATA';
		if($_templateFormat==1) {
		    $_name =~ s/\$[1-9]\$[^\s"]+/TEMPLATE-CENSORED/o if defined($_name);
		    $_val =~ s/\$[1-9]\$[^\s"]+/TEMPLATE-CENSORED/o if defined($_val);
		}		
	    }

	    if($_depth < $_currentDepth) {
		if($fmt eq 'ascii') {
		    $_configTxt .= __generatePadsDown($_currentDepth, $_depth+1);
		}		
	    }

	    $_name =~ s/^\s+//go if defined($_name);
	    $_name =~ s/\s+$//go if defined($_name);
	    $_val =~ s/^\s+//go if defined($_val);
	    $_val =~ s/\s+$//go if defined($_val);
	    
	    if($fmt eq 'set') {
		my $_newLine .= 'set '.join(' ', map { $_depthInfo->{$_}; } sort {$a <=> $b} keys %{$_depthInfo}).' '.$_name.(defined($_val) ? ' '.$_val : '').(defined($comment) ? ' ## '.$comment : '')."\n";
#		$_newLine =~ s/ {2,}/ /go;
		$_configTxt .= $_newLine;
	    }
	    else {
		my $_pad = __generatePad($_depth+1);
		my $_pout = [];
		push(@{$_pout}, $_name) if defined($_name) && $_name ne '';
		push(@{$_pout}, $_val) if defined($_val) && $_val ne '';

		
		$_configTxt .= $_pad.join(' ', @{$_pout}).';'.(defined($comment) ? ' ## '.$comment : '')."\n";

#		if(defined($comment)) {
#		    die $_configTxt.','.$_name.','.$_val if $_configTxt =~ /\s\s/o;
#		}
		
#		if($_name =~ /on-loss-of-keepalives/o) {
#		    die '['.$_name.'/'.$_val.']';
#		}
	    }
	}
	elsif($_type eq 'LEAF' || $_type eq 'LEAF-EMPTY') {

	    $_depthInfo->{$_depth} = $_name;

	    if($_depth < $_currentDepth) {
		map {
		    delete $_depthInfo->{$_};
		} grep { $_ > $_depth } keys %{$_depthInfo};

		if($fmt eq 'set') {
		    # nothing for sets.
		}
		else {
		    $_configTxt .= __generatePadsDown($_currentDepth, $_depth);
		}
	    }

	    if($_depth == $_currentDepth) {
		if($fmt eq 'set') {
		}
		else {
		    $_configTxt .= __generatePadsDown($_depth, $_depth);
		}
	    }

	    if($fmt eq 'set') {
	    }
	    else {
		my $_pad = __generatePad($_depth);
		$_configTxt .= $_pad.$_name." {\n";
	    }

	}
	else {
	    die "UNKNOWN TYPE?? ".$_type." DEPTH[".$_depth."] PREVTYPE = ".$_prevType;
	}
	$_currentDepth = $_depth;
	$_prevType = $_type;

	$_x += $_shift;
    }
    
    if($fmt eq 'set') {
    }
    else {
	$_configTxt .= __generatePadsDown($_currentDepth, 1);
    }

    return $_configTxt;
}

sub __populateKeys($$$$;$) {
    my ($self, $__leafNode, $__keyArr, $__valHsh, $__unique) = (@_);
    return -1 if ref($__keyArr) ne 'ARRAY' || ref($__leafNode) ne 'HASH' || ref($__valHsh) ne 'HASH';
    my $_c=0;

    map {
	my $_key = $_;
	my $_val = $__valHsh->{$_};
	my $_unique = (defined($__unique) && $__unique == 1 ? 1 : 0);

	$_key =~ s/\\s/ /go;
	$_key =~ s/\s$//o;
	$_key =~ s/^\s+//o;

	if($_key eq '@') {
	    $_key = $_val;
	    $_val = undef;
	    $_unique = 1;
	}
	if(!$_unique && defined($__leafNode->{$_key})) {
	    my $_tmp = $__leafNode->{$_key};
	    $__leafNode->{$_key} = [$_tmp];
	}
	if(ref($__leafNode->{$_key}) eq 'ARRAY') {
	    push(@{$__leafNode->{$_key}}, $_val);
	}
	else {
	    if(ref($_key) eq 'ARRAY') {
		map { $self->__assignOrderedItem($__leafNode, $_, $_val); } @{$_key};
	    }
	    else {
		$self->__assignOrderedItem($__leafNode, $_key, $_val, $_unique);
	    }
	}
	$_c++;
    } @{$__keyArr};
    return $_c;
}

# @DEPRECATED
sub add_index($$) {
    my ($__hsh, $__name) = (@_);

    if(ref($__hsh->{'__order'}) ne 'ARRAY') {
	my $_newOrder = [];
	my $_newIdx = {};

	$__hsh->{'__idx'} = $_newIdx;
	$__hsh->{'__order'} = $_newOrder;
    }

    if(!defined($__hsh->{'__idx'}{$__name})) {
	push(@{$__hsh->{'__order'}}, $__name);
	$__hsh->{'__idx'}{$__name} = 1;
	return(1);
    }
    return(0);
}

# @DEPRECATED
sub block_start($$) {
    my ($self, $_newblock) = (@_);

#    print "block_start(".$_newblock.")\n";
    
    if ( defined ( $self->{c}{$_newblock} ) ) {
	$self->__debug(0, __LINE__, '/**** BUG Block<'.$_newblock.'> already defined.');
	return(0);
    }

    my $_nhsh = {'__parent' => $self->{c},
		 '__name'   => $_newblock};

    add_index($self->{c}, $_newblock);
    
    $self->{c}{$_newblock} = $_nhsh;
    $self->{c} = $_nhsh;

    return(1);
}

# @DEPRECATED
sub opt($$$) {
    my ($self, $_k, $_v) = (@_);

#    print "opt(".$_k.", ".$_v.")\n";
    
    if ( defined ( $self->{c}{$_k} ) && ref($self->{c}{$_k}) eq 'ARRAY' ) {
	$self->__debug(0, __LINE__, '/*** BUG:opt('.$_k.', '.$_v.') Key is defined as array???');
	return(0);
    }

    if ( $_k =~ /^__/o ) {
	$self->__debug(0, __LINE__, '/*** BUG:opt('.$_k.', '.$_v.') Key is __reserved.');
	return(0);
    }

    add_index($self->{c}, $_k);
    
    $self->{c}{$_k} = $_v if defined($_v);

    return( ( defined ( $self->{c}{$_k} ) ? $self->{c}{$_k} : undef ) );
}

# @DEPRECATED
sub block_end($) {
    my ($self) = (@_);

#    print "block_end()\n";
    
    if ( !defined($self->{c}{__parent}) ) {
	$self->__debug(0, __LINE__, '/*** BUG block_end() no Parent defined? self->{c} = '.Data::Dumper::Dumper($self->{c}));
	return(0);
    }

    my $parent = $self->{c}{__parent};
    $self->{c}{__parent} = undef;
    delete $self->{c}{__parent};

    $self->{c} = $parent;
    
    return(1);
}

sub add($$) {
    my ($self, $_d) = (@_);
    $self->{data} .= $_d;
    return(1);
}


package JunosCFG;

sub __debug { my $s=shift; return ( defined($s->{opts}{DebugFunc}) ? $s->{opts}{DebugFunc}(__PACKAGE__, @_) : 0 ); }

sub new($$) {
    my ($class, $opts) = (@_);
    my $self = {opts => $opts};

    bless $self, $class;

    return $self;
}

# @SLOW (Very)
sub diffCfg($$$$) {
    my ($self, $_src, $_dst) = (@_);
    my $_result;

    my $_cmp_q = [];

    push(@{$_cmp_q}, [$_result, $_src, $_dst, 'ALL']);
    push(@{$_cmp_q}, [$_result, $_dst, $_src, 'ADD']);

    ##################################################
    # Comparison tree result out of comparing src/dst
    while(my $_cmp_qi = shift(@{$_cmp_q})) {
	my $_mode = (defined($_cmp_qi->[3]) && $_cmp_qi->[3] eq 'ADD' ? 'ADD' : 'ALL');
	
	######################
	# No Comp-1 ????
	if ( ! defined ($_cmp_qi->[1]) ) {
	    $self->__debug(0, __LINE__, '/*** BUG walkDiff source undefined?');
	    return(undef);
	}

	my $_rhash_ptr;
	if ( defined ( $_cmp_qi->[0] ) ) {
	    $_rhash_ptr = $_cmp_qi->[0];
	}
	else {
	    $_rhash_ptr = (ref($_cmp_qi->[1]) eq 'ARRAY' ? [] : {});
	    $_result = $_rhash_ptr if !defined($_result);
	}

	######################
	# Comp-2 totally gone
	if ( ! defined ( $_cmp_qi->[2] ) ) {
	    #	    print "GONE ".Data::Dumper::Dumper($_cmp_qi->[2])."\n";
	    if($_mode eq 'ADD') {
		$_rhash_ptr->{'__added'} = 'key';
		$_rhash_ptr->{'__dst'} = $_cmp_qi->[1];
	    }
	    else {
		$_rhash_ptr->{'__deleted'} = 'key';
		$_rhash_ptr->{'__src'} = $_cmp_qi->[1];
	    }
#	    $_rhash_ptr = {'__deleted' => 'key',
#			   '__src'     => $_cmp_qi->[1]};
	    next;
	}
	################################
	# Comp-1/Comp-2 types mismatch
	if ( $_mode eq 'ALL' && ref($_cmp_qi->[1]) ne ref($_cmp_qi->[2]) ) {
	    $_rhash_ptr = {'__diff_v' => ref($_cmp_qi->[1]).'-TO-'.ref($_cmp_qi->[2]),
			   '__src'    => $_cmp_qi->[1],
			   '__dst'    => $_cmp_qi->[2]};
	    next;
	}

	#####################
	# Comps are hashes
	if ( ref ( $_cmp_qi->[1] ) eq 'HASH' ) {

	    my $k_src      = ( defined ( $_cmp_qi->[1] ) ? $_cmp_qi->[1]{__name} : undef );
	    my $k_dst      = ( defined ( $_cmp_qi->[2] ) ? $_cmp_qi->[2]{__name} : undef );

	    if ( ! defined ($k_src) ) {
		$self->__debug(0, __LINE__, '/*** BUG walkDiff source<'.
			       (defined($k_src)?$k_src:'undef').'>/dest<'.
			       (defined($k_dst)?$k_dst:'undef').'> source hash does not have a name???');
		return(undef);
	    }
	    
	    my $_changes = 0;
	    my $_childs  = 0;

#	    print "cwmp_qi = ".Data::Dumper::Dumper($_cmp_qi->[1])."\n";
	    
	    ############################
	    # Iterate Comp-1 HASH keys
	    foreach my $_hk (keys %{$_cmp_qi->[1]}) {

		###########################################
		# Key-1 type is HASH/ARRAY, push into queue
		if ( ref($_cmp_qi->[1]{$_hk}) eq 'HASH' ||
		     ref($_cmp_qi->[1]{$_hk}) eq 'ARRAY' ) {
		    if ( $_hk !~ /^__/o ) {
			if ( ref($_cmp_qi->[1]{$_hk}) eq 'HASH' ) {
			    $_rhash_ptr->{$_hk} = ( defined ( $self->{opts}{cmpInfo} ) ?
						    {'__cmp' => ref($_cmp_qi->[1]{$_hk})} : {} );
			}
			else {
			    # TODO:array/hash thing
			    $_rhash_ptr->{$_hk} = [];
			    #                           $_rhash_ptr->{$_hk} = ( defined ( $self->{opts}{cmpInfo} ) ?
			    #                                                   {'__cmp' => ref($_cmp_qi->[1]{$_hk})} : p[ );
			}
			push(@{$_cmp_q}, [$_rhash_ptr->{$_hk}, $_cmp_qi->[1]{$_hk}, $_cmp_qi->[2]{$_hk}, $_mode]);
			$_childs++;
		    }
		}
		###########################################
		# Key-1 type is a value, Key-2 deleted
		elsif ( $_mode eq 'ALL' && !defined($_cmp_qi->[1]{$_hk}) ) {
		    $_rhash_ptr->{$_hk} = {'__deleted' => 'key',
					   '__src'     => $_cmp_qi->[1]{$_hk}};
		    $_changes++;
		}
		###########################################
		# Key-1 type is a value, Key-2 exists but type not same
		elsif ( $_mode eq 'ALL' && ref($_cmp_qi->[2]{$_hk}) eq 'HASH' ||
			ref($_cmp_qi->[2]{$_hk}) eq 'ARRAY' ) {

		    ####################################################################################
		    # TODO:Cover hashes turned into arrays - pull the first key and see the difference.

		    $_rhash_ptr->{$_hk} = {'__diff_v' => ref($_cmp_qi->[2]{$_hk}).'-TO-'.ref($_cmp_qi->[2]{$_hk}),
					   '__src'    => $_cmp_qi->[1]{$_hk},
					   '__dst'    => $_cmp_qi->[2][$_hk]};
		}
		###################
		# Value comparison
		else {
		    ##################
		    # Value mismatch
		    if ($_mode eq 'ALL' &&
			((defined($_cmp_qi->[1]{$_hk}) && !defined($_cmp_qi->[2]{$_hk})) ||
			(!defined($_cmp_qi->[1]{$_hk}) && defined($_cmp_qi->[2]{$_hk})) ||
			($_cmp_qi->[1]{$_hk} ne $_cmp_qi->[2]{$_hk} ))) {
			$_rhash_ptr->{$_hk} = {'__diff_v' => 'values',
					       '__src'    => $_cmp_qi->[1]{$_hk},
					       '__dst'    => $_cmp_qi->[2]{$_hk}};
		    }
		}
	    }
	}
	#####################
	# Comp-1 is an array
	elsif( ref($_cmp_qi->[1]) eq 'ARRAY' ) {

	    my $arr = [];
	    ##################
	    # Compare indexes
	    for(my $_x=0;$_x<=(scalar(@{$_cmp_qi->[1]})-1);$_x++) {
		if ( defined($_cmp_qi->[2][$_x]) ) {

		    my $_nhsh =
			( defined ( $self->{opts}{cmpInfo} ) ?
			  {'__cmp' => ref($_cmp_qi->[1][$_x])} : {} );

		    #                   $_rhash_ptr->{'__array'}[$_x] = $_nhsh;   # TODO:array/hash thing
		    $_rhash_ptr->[$_x] = $_nhsh;

		    push(@{$_cmp_q}, [$_nhsh, $_cmp_qi->[1][$_x], $_cmp_qi->[2][$_x], $_mode]);

		}
		else {
		    my $_thsh = {};

		    foreach my $_k (grep {!/^__parent/o} keys %{$_cmp_qi->[1][$_x]}) {
			$_thsh->{$_k} = $_cmp_qi->[1][$_x]{$_k};
			if ( ref($_thsh->{$_k}) eq 'HASH' && defined($_thsh->{$_k}{__parent}) ) {
			    $_thsh->{$_k}{__parent} = undef;
			    delete $_thsh->{$_k}{__parent};
			}
		    }

		    $_rhash_ptr->[$_x] = {'__deleted' => 'index-'.($_x+1),
					  #                                         '__src'     => $_cmp_qi->[1][$_x]};
					  '__src'     => $_thsh};
		}
	    }
	    if ( scalar(@{$_cmp_qi->[1]}) <= scalar(@{$_cmp_qi->[2]}) ) {
#		print "ADDED ".(scalar(@{$_cmp_qi->[2]}) - scalar(@{$_cmp_qi->[1]}))." Items\n";
		for(my $_x=(scalar(@{$_cmp_qi->[1]}));$_x<=(scalar(@{$_cmp_qi->[2]})-1);$_x++) {

		    my $_thsh = {};
		    #                   print "Dump[".$_x."] ".Data::Dumper::Dumper($_cmp_qi->[2][$_x])."\n";
		    #                   exit(42);
		    foreach my $_k (grep {!/^__/o} keys %{$_cmp_qi->[2][$_x]}) {
			$_thsh->{$_k} = $_cmp_qi->[2][$_x]{$_k};
		    }
#		    print "ADDED ".Data::Dumper::Dumper($_thsh)."\n";
		    
		    my $_nHsh = {'__added' => 'index-'.$_x,
				 '__dst' => $_thsh};
		    
#		    $_rhash_ptr->[$_x] = {'__added' => 'index-'.$_x,
#					  #                                         '__src'     => $_cmp_qi->[1][$_x]};
		    #					  '__dst'     => $_thsh};
		    $_rhash_ptr->[$_x] = $_nHsh;
		}
	    }
	}
	####################
	# Must be glob.
	else {
	    $self->__debug(6, __LINE__, '/**** BUG walkDiff-is '.ref($_cmp_qi->[2]).'? source REF is '.ref($_cmp_qi->[1]));
	    return(undef);
	}
    }

    #    $self->__debug(0, __PACKAGE__, 'Result = '.Data::Dumper::Dumper($_result));
    #    exit(42);

    ##################
    # Delete empties.
    # Would use generic tree travelsal package if:
    # - This would not need leafs->root tree traversing
    #    my $flags = [[[$_result, undef]]];
    my $flags = [[[$_result, undef, undef]]];
    if ( defined($self->{opts}{cmpEmpty}) && $self->{opts}{cmpEmpty} == 0 ) {

	while(@{$flags}) {
	    my $_depth;

	    for(my $_dguess=(scalar(@{$flags})-1);$_dguess>-1;$_dguess--) {
		if ( scalar(@{$flags->[$_dguess]}) ) {
		    $_depth = $_dguess;
		    last;
		}
		$flags->[$_dguess] = undef;
		delete $flags->[$_dguess];
	    }

	    last if !defined($_depth);

	    my $_dq    = $flags->[$_depth];

	    while(my $_nodeq = shift(@{$_dq})) {
		my $_node   = $_nodeq->[0];
		my $_parent = $_nodeq->[1];
		my $_pidx   = $_nodeq->[2];

		next if !defined($_node);

		#               $self->__debug(0, __PACKAGE__, '[Depth: '.$_depth.'] Node='.$_node.' Parent='.(defined($_parent)?$_parent:'none').' pidx='.(defined($_pidx)?$_pidx:'-'));

		if ( ref($_node) eq 'ARRAY' ) {
		    if ( List::MoreUtils::all { ref $_ eq 'HASH' && !keys %{ $_ } } @{ $_node }) {

			if ( defined($_parent) && defined($_pidx) ) {
			    $_node = undef;
			    if (ref($_parent)   eq 'HASH')  { $_parent->{$_pidx} = undef; delete $_parent->{$_pidx}; }
			    elsif(ref($_parent) eq 'ARRAY') { $_parent->[$_pidx] = undef; delete $_parent->[$_pidx]; }

			    push(@{$flags->[$_depth-1]}, [$_parent, undef, undef]);
			}
			###############
			# must be root
			#                       elsif(!defined($_parent)) {
			#                           if (ref($_result)   eq 'HASH')  { $_result->{$_pidx} = undef; delete $_parent->{$_pidx}; }
			#                           elsif(ref($_result) eq 'ARRAY') { $_parent->[$_pidx] = undef; delete $_parent->[$_pidx]; }
			#                       }
		    }
		    else {
			for(my $_idx=0;$_idx<=(scalar(@{$_node})-1);$_idx++) {
			    push(@{$flags->[$_depth+1]}, [$_node->[$_idx], $_node, $_idx]);
			}
		    }
		}
		elsif ( ref($_node) eq 'HASH' ) {
		    my ($_items, $_pitems) = ([],[]);
		    @{$_items}  = grep {!/^__/o} keys %{$_node};
		    @{$_pitems} = grep {/^__/o} keys %{$_node};
		    #                   @{$_items} = keys %{$_node};
		    if ( scalar(@{$_items}) ) {
			foreach my $_k (@{$_items}) {
			    if( ref ($_node->{$_k}) eq 'ARRAY' || ref($_node->{$_k}) eq 'HASH' ) {
				push(@{$flags->[$_depth+1]}, [$_node->{$_k}, $_node, $_k]);
			    }
			}
		    }
		    elsif(!scalar(@{$_pitems})) {
			if ( defined($_parent) && defined($_pidx) ) {
			    #                           $_node = undef;
			    if (ref($_parent)   eq 'HASH')  { $_parent->{$_pidx} = undef; delete $_parent->{$_pidx}; }
			    elsif(ref($_parent) eq 'ARRAY') { $_parent->[$_pidx] = undef; delete $_parent->[$_pidx]; }

			    push(@{$flags->[$_depth-1]}, [$_parent, undef, undef]);

			}
			# must be root
			elsif(!defined($_parent)) {
			    # KTODO handle root nodes.
			}
		    }
		}
	    }
	}
    }
    return($_result);
}

sub parse($$) {
    my ($self, $_exp_data) = (@_);

    my $_lc = 0;

    my $from_a_handle = (ref($_exp_data)
			 ? (ref($_exp_data) eq 'GLOB'
			    || UNIVERSAL::isa($_exp_data, 'GLOB')
			    || UNIVERSAL::isa($_exp_data, 'IO::Handle'))
			 : (ref(\$_exp_data) eq 'GLOB'));

    my @lines;
    if(!$from_a_handle) {
	@lines = split("\n", $_exp_data);
    }

    my $_cfg = new JunosCFG::Cfg($self->{opts});

    my ($c_key, $_v_buffer);

    my $_currentDepths = {};
    
    while(1) {

	if($from_a_handle) {
	    $_ = <$_exp_data>;
	    chomp if defined($_);
	}
	else {
	    $_ = shift(@lines);
	}
	last if !defined($_);
	
	$_lc++;
	s/\015$//o;

      reinterprete:
	my $_file;
	
	my $_d = $_;
	$_d =~ s/^[\s\t]+//o;
	$_d =~ s/[\s\t]+$//o;

	if ( defined ( $c_key ) ) {
	    if ( $_d =~ s/(.*)";//o ) {
		$_v_buffer .= $1;

#		print "Append-End<".$c_key."> _v_buffer<".$_v_buffer.">\n";

		
		$_cfg->__assignAtCurrentDepth($_currentDepths, $c_key, $_v_buffer);
#		$_cfg->opt($c_key, $_v_buffer);
		($c_key, $_v_buffer) = (undef, undef);
	    }
	    else {
#		print "Append-Cont<".$c_key."> _v_buffer<".$_v_buffer.">\n";
		$_v_buffer .= $_d;
		$_d = '';
	    }
	}

	my $_o = $_d;

	$_d =~ s/\s*//o;
	$_d =~ s/\s*\/\*.+?\*\/\s*//go;
	$_d =~ s/^#.+//o;
	$_d =~ s/;\s*#.+/;/o;

#	die 'Original<'.$_o.'> Destination<'.$_d.'>' if $_d =~ /SECRET-DATA/o;
	
	if ($_d eq '') {
	    next;
	} elsif($_d =~ /^\s*(.+?)\s*\{\s*$/o) {
	    my $_leaf = $1;
	    $_leaf =~ s/\s/\\s/go;
	    #	    $_cfg->block_start($1);
	    my $_depth = scalar(keys %{$_currentDepths})+1;

	    $_currentDepths->{$_depth} = $_leaf;
	} elsif($_d =~ /^}$/o) {
	    #	    $_cfg->block_end();	    
	    my $_depth = scalar(keys %{$_currentDepths})-1;
	    map { delete $_currentDepths->{$_}; }
	    grep { $_ > $_depth; } keys %{$_currentDepths};	    
	} elsif($_d =~ /^([^\s;]+)\s*([^;]*;*).*$/o) {
	    ($c_key, $_v_buffer) = ($1, $2);

	    if ( $_v_buffer =~ /([^;]*);$/o ) {
		my $_val = $1;

		$_val = 'undef' if !defined($_val);
		if(!defined($_val)) {
		    $_val = $c_key;
		    $c_key = '@';
		}
		# avoid multi-key-value collisions
		elsif($_val !~ /\s/o) {
		    $c_key = $c_key.(defined($_val) && $_val ne '' && defined($c_key) && $c_key ne '' ? ' ' : '').$_val;
		    $_val = undef;
		}
		#		$_cfg->opt($c_key, $1);

		$_cfg->__assignAtCurrentDepth($_currentDepths, $c_key, $_val);
		($c_key, $_v_buffer) = (undef, undef);

	    }
	    else {
		print "Append-Start<".$c_key."> _v_buffer<".$_v_buffer.">\n";
	    }
	}
	else {
	    $self->__debug(0, __LINE__, 'parseCfg['.$_lc.']::Could not handle<'.$_d.'>');
	}

    }

    return $_cfg;
}

sub format_diff_text_OLD($$) {
    my ($self, $_res) = (@_);

    my $_fq = [[$_res, '/']];

    my $report = '';

    while(my $qi = shift(@{$_fq})) {
	my $d     = $qi->[0];
	my $cpath = $qi->[1];

	#    __debug(__PACKAGE__, 0, __LINE__, 'Processing '.$cpath.' D='.$d);

	if ( ref($d) eq 'ARRAY' ) {
	    for(my $z=0;$z<=(scalar(@{$d})-1);$z++) {
		if (defined($d->[$z])) {
		    push(@{$_fq}, [$d->[$z], $cpath.'['.($z+1).']/']);
		}
	    }
	}
	elsif ( ref($d) eq 'HASH') {
	    if ( defined($d->{__diff_v}) ) {
		if ( $d->{__diff_v} eq 'values' ) {
		    my $fpath = $cpath;
		    $fpath =~ s/\/$//o;
		    $report .=
			'**** Value Change '.$fpath."\n".'<- '.(defined($d->{__src}) ? $d->{__src} : 'undef')."\n".
			'-> '.(defined($d->{__dst}) ? $d->{__dst} : 'undef')."\n";
		}
		else {
		    die 'could not handle diff_v = '.Data::Dumper::Dumper($d);
		}

	    }
	    elsif ( defined ($d->{__deleted}) ) {
		if ( $d->{__deleted} =~ /^index/o ) {
		    $report .= '**** Deleted '.$cpath."\n";
		    foreach my $_k (grep {!/^__/o} keys %{$d->{__src}}) {
			$report .= $_k.' << '.$d->{__src}{$_k}."\n";
		    }
		}
		elsif($d->{__deleted} eq 'key') {
		    $report .= '**** Deleted '.$cpath."\n";
		}
		else {
		    die 'could not handle<'.$cpath.'> deleted = '.Data::Dumper::Dumper($d);
		}
	    }
	    elsif( defined ($d->{__added}) ) {
		if ( $d->{__added} =~ /^index/o ) {
		    $report .= '**** Added '.$cpath."\n";
		    foreach my $_k (grep {!/^__/o} keys %{$d->{__dst}}) {
			$report .= $_k.' >> '.$d->{__dst}{$_k}."\n";
		    }
		}
		else {
		    die 'could not handle added = '.Data::Dumper::Dumper($d);
		}
	    }
	    else {
		foreach my $_k (grep {!/^__/o} keys %{$d}) {
		    push(@{$_fq}, [$d->{$_k}, $cpath.$_k.'/']);
		}
	    }
	}
	else {
	    __debug(__PACKAGE__, 0, __LINE__, 'Houston we have a problem.. what is '.(defined($qi)?$qi:'undef').' qi = '.Data::Dumper::Dumper($qi));
	    exit(1);
	}
    }
    return $report;
}

sub format_cfg_text_OLD($$) {
    my ($self, $_res) = (@_);

    my $_fq = [[$_res, '/']];

    my $report = '';

    while(my $qi = shift(@{$_fq})) {
	my $d     = $qi->[0];
	my $cpath = $qi->[1];

	if ( ref($d) eq 'ARRAY' ) {
	    for(my $z=0;$z<=(scalar(@{$d})-1);$z++) {
		if (defined($d->[$z])) {
		    push(@{$_fq}, [$d->[$z], $cpath.'['.($z+1).']/']);
		}
	    }
	}
	elsif ( ref($d) eq 'HASH') {

	    my $c=0;
	    foreach my $_k (grep {!/^__/o} keys %{$d}) {
		if ( ref($d->{$_k}) eq 'ARRAY' || ref($d->{$_k}) eq 'HASH' ) {
		    push(@{$_fq}, [$d->{$_k}, $cpath.$_k.'/']);
		}
		else {
		    $c++;
		    if ( $c==1 ) {
			$report .= "**** Addition ".$cpath."\n";
		    }
		    $report .= $_k.' >> '.$d->{$_k}."\n";
		}
	    }

	}
	else {
	    $self->__debug(0, __LINE__, 'Houston we have a problem.. what is '.(defined($qi)?$qi:'undef').' qi = '.Data::Dumper::Dumper($qi));
	    return(undef);
	}
    }

    return $report;
#    print $report;
}


sub parseCfg_OLD($$) {
    my ($self, $_exp_data) = (@_);

    my $_lc = 0;

    my $from_a_handle = (ref($_exp_data)
			 ? (ref($_exp_data) eq 'GLOB'
			    || UNIVERSAL::isa($_exp_data, 'GLOB')
			    || UNIVERSAL::isa($_exp_data, 'IO::Handle'))
			 : (ref(\$_exp_data) eq 'GLOB'));

    my @lines;
    if(!$from_a_handle) {
	@lines = split("\n", $_exp_data);
    }

    my $_cfg = new JunosCFG::Cfg($self->{opts});

    my ($c_key, $_v_buffer);
    
    while(1) {

	if($from_a_handle) {
	    $_ = <$_exp_data>;
	    chomp if defined($_);
	}
	else {
	    $_ = shift(@lines);
	}
	last if !defined($_);
	
	$_lc++;
	s/\015$//o;

      reinterprete:
	my $_file;
	
	my $_d = $_;
	$_d =~ s/^[\s\t]+//o;
	$_d =~ s/[\s\t]+$//o;

	if ( defined ( $c_key ) ) {
	    if ( $_d =~ s/(.*)";//o ) {
		$_v_buffer .= $1;
		
		$_cfg->opt($c_key, $_v_buffer);
		($c_key, $_v_buffer) = (undef, undef);
	    }
	    else {
		$_v_buffer .= $_d;
		$_d = '';
	    }
	}

	my $_o = $_d;

	$_d =~ s/\s*//o;
	$_d =~ s/\s*\/\*.+?\*\/\s*//go;
	$_d =~ s/^#.+//o;
	$_d =~ s/;\s*#.+/;/o;

	die 'Original<'.$_o.'> Destination<'.$_d.'>' if $_d =~ /SECRET-DATA/o;
	
	if ($_d eq '') {
	    next;
	} elsif($_d =~ /^(.+?)\s*\{$/o) {
	    $_cfg->block_start($1);
	} elsif($_d =~ /^}$/o) {
	    $_cfg->block_end();
	} elsif($_d =~ /^([^\s;]+)\s*(.*);.*$/o) {
	    ($c_key, $_v_buffer) = ($1, $2);

	    if ( $_v_buffer =~ /(.+)$/o ) {
		$_cfg->opt($c_key, $1);
		($c_key, $_v_buffer) = (undef, undef);
	    }
	}
	else {
	    $self->__debug(0, __LINE__, 'parseCfg['.$_lc.']::Could not handle<'.$_d.'>');
	}

    }

    return $_cfg;
}

1;

