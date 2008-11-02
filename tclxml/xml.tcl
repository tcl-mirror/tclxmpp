# xml.tcl --
#
#       This file provides generic XML services for all implementations.
#       This file supports Tcl 8.1 regular expressions.
#
#       See tclparser.tcl for the Tcl implementation of a XML parser.
#
# Copyright (c) 1998-2000 Zveno Pty Ltd
# http://www.zveno.com/
#
# Zveno makes this software and all associated data and documentation
# ('Software') available free of charge for any purpose.
# Copies may be made of this Software but all of this notice must be included
# on any copy.
#
# The Software was developed for research purposes and Zveno does not warrant
# that it is error free or fit for any purpose.  Zveno disclaims any
# liability for all claims, expenses, losses, damages and costs any user may
# incur as a result of using, copying or modifying the Software.
#
# Copyright (c) 1997 Australian National University (ANU).
#
# ANU makes this software and all associated data and documentation
# ('Software') available free of charge for any purpose. You may make copies
# of the Software but you must include all of this notice on any copy.
#
# The Software was developed for research purposes and ANU does not warrant
# that it is error free or fit for any purpose.  ANU disclaims any
# liability for all claims, expenses, losses, damages and costs any user may
# incur as a result of using, copying or modifying the Software.
#
# $Id$

package require Tcl 8.1

package provide xmldefs 2.0

package require -exact sgml 1.8

namespace eval xml {

    namespace export qnamesplit

    # Convenience routine
    proc cl x {
        return "\[$x\]"
    }

    # Define various regular expressions

    # Characters
    variable Char $::sgml::Char

    # white space
    variable Wsp " \t\r\n"
    variable allWsp [cl $Wsp]*
    variable noWsp [cl ^$Wsp]

    # Various XML names and tokens

    variable NameChar $::sgml::NameChar
    variable Name $::sgml::Name
    variable Names $::sgml::Names
    variable Nmtoken $::sgml::Nmtoken
    variable Nmtokens $::sgml::Nmtokens

    # XML Namespaces names

    # NCName ::= Name - ':'
    variable NCName $::sgml::Name
    regsub -all : $NCName {} NCName
    variable QName (${NCName}:)?$NCName ; # (Prefix ':')? LocalPart

    # table of predefined entities

    variable EntityPredef
    array set EntityPredef {
        lt <   gt >   amp &   quot \"   apos '
    }

    # Expressions for pulling things apart
    #variable tokExpr <(/?)([::xml::cl ^$::xml::Wsp>/]+)([::xml::cl $::xml::Wsp]*[::xml::cl ^>]*)>
    variable tokExpr1 {<()(\?[^\s>]+)(([^>]+|[^?]>)*\?)>}
    variable tokExpr2 {<()(![^\s>]+)(\s*[^>]*)>}
    variable tokExpr3 {<(/?)([^!?][^\s>/]*)((\s*[^'\"\s]+\s*=\s*('[^']*'|\"[^\"]*\"))*\s*/?)>}
    variable substExpr "\}\n{\\2} {\\1} {\\3} \{"

}

###
###     Exported procedures
###

# xml::qnamesplit --
#
#       Split a QName into its constituent parts:
#       the XML Namespace prefix and the Local-name
#
# Arguments:
#       qname       XML Qualified Name (see XML Namespaces [6])
#
# Results:
#       Returns prefix and local-name as a Tcl list.
#       Error condition returned if the prefix or local-name
#       are not valid NCNames (XML Name)

proc xml::qnamesplit qname {
    variable NCName
    variable Name

    set prefix {}
    set localname $qname
    if {[regexp : $qname]} {
        if {![regexp ^($NCName)?:($NCName)\$ $qname discard prefix localname]} {
            return -code error "name \"$qname\" is not a valid QName"
        }
    } elseif {![regexp ^$Name\$ $qname]} {
        return -code error "name \"$qname\" is not a valid Name"
    }

    return [list $prefix $localname]
}

###
###     General utility procedures
###

# xml::noop --
#
# A do-nothing proc

proc xml::noop args {}

### Following procedures are based on html_library

# xml::zapWhite --
#
#       Convert multiple white space into a single space.
#
# Arguments:
#       data        plain text
#
# Results:
#       As above

proc xml::zapWhite data {
    regsub -all "\[ \t\r\n\]+" $data { } data
    return $data
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
