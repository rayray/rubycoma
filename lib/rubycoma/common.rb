module RubyCoMa
  require 'cgi'
  module Common
    STRINGREGEX_ESCAPABLE           = '[!"#$%&\'()*+,./\\:;<=>?@\[\]^_`{|}~-]'
    STRINGREGEX_ESCAPED_CHAR        = '\\\\' << STRINGREGEX_ESCAPABLE
    STRINGREGEX_REG_CHAR            = '[^\\\\()\\x00-\\x20]'
    STRINGREGEX_IN_PARENS_NOSP      = '\\((' << STRINGREGEX_REG_CHAR << '|' << STRINGREGEX_ESCAPED_CHAR << ')*\\)'
    STRINGREGEX_TAGNAME             = '[A-Za-z][A-Za-z0-9]*'
    STRINGREGEX_ATTRIBUTENAME       = '[a-zA-Z_:][a-zA-Z0-9:._-]*'
    STRINGREGEX_UNQUOTEDVALUE       = '[^"\'=<>`\\x00-\\x20]+'
    STRINGREGEX_SINGLEQUOTEDVALUE   = '\'[^\']*\''
    STRINGREGEX_DOUBLEQUOTEDVALUE   = '"[^\"]*"'
    STRINGREGEX_ATTRIBUTEVALUE      = '(?:' << STRINGREGEX_UNQUOTEDVALUE << '|' << STRINGREGEX_SINGLEQUOTEDVALUE << '|' << STRINGREGEX_DOUBLEQUOTEDVALUE << ')'
    STRINGREGEX_ATTRIBUTEVALUESPEC  = '(?:' << '\s*=' << '\s*' << STRINGREGEX_ATTRIBUTEVALUE << ')'
    STRINGREGEX_ATTRIBUTE           = '(?:' << '\s+' << STRINGREGEX_ATTRIBUTENAME << STRINGREGEX_ATTRIBUTEVALUESPEC << '?)'
    STRINGREGEX_OPENTAG             = '<' << STRINGREGEX_TAGNAME << STRINGREGEX_ATTRIBUTE << '*' << '\s*/?>'
    STRINGREGEX_CLOSETAG            = '</' << STRINGREGEX_TAGNAME << '\s*[>]'
    STRINGREGEX_HTMLCOMMENT         = '<!---->|<!--(?:-?[^>-])(?:-?[^-])*-->'
    STRINGREGEX_PROCINSTRUCTION     = '[<][?].*?[?][>]'
    STRINGREGEX_DECLARATION         = '<![A-Z]+' << '\s+[^>]*>'
    STRINGREGEX_CDATA               = "<!\\[CDATA\\[[\\s\\S]*?\\]\\]>"
    STRINGREGEX_HTMLTAG             = '(?:' << STRINGREGEX_OPENTAG << '|' << STRINGREGEX_CLOSETAG << '|' << STRINGREGEX_HTMLCOMMENT << '|' << STRINGREGEX_PROCINSTRUCTION << '|' << STRINGREGEX_DECLARATION << '|' << STRINGREGEX_CDATA << ')'

    REGEX_NONSPECIALCHARS       = /^[^\n`\[\]\\!<&*_]+/m
    REGEX_ENTITY                = /^&(?:#x[a-f0-9]{1,8}|#[0-9]{1,8}|[a-z][a-z0-9]{1,31});/
    REGEX_WHITESPACECHARACTER   = /^\s/
    REGEX_WHITESPACE            = /^\s+/
    REGEX_PUNCTUATION           = /^[\u2000-\u206F\u2E00-\u2E7F\\'!"#\$%&\(\)\*\+,\-\.\/:;<=>\?@\[\]\^_`\{\|\}~]/
    REGEX_ESCAPABLE             = Regexp.new('^' << STRINGREGEX_ESCAPABLE)
    REGEX_SPACES                = /^ */
    REGEX_LINKDESTBRACES        = Regexp.new('^(?:[<](?:[^<>\\n\\\\\\x00]' << '|' << STRINGREGEX_ESCAPED_CHAR << '|' << '\\\\)*[>])')
    REGEX_LINKDEST              = Regexp.new('^(?:' << STRINGREGEX_REG_CHAR << '+|' << STRINGREGEX_ESCAPED_CHAR << '|\\\\|' << STRINGREGEX_IN_PARENS_NOSP << ')*')
    REGEX_LINKTITLE             = Regexp.new('^(?:"(' << STRINGREGEX_ESCAPED_CHAR << '|[^"\\x00])*"' <<
                                                 '|' <<
                                                 '\'(' << STRINGREGEX_ESCAPED_CHAR << '|[^\'\\x00])*\'' <<
                                                 '|' <<
                                                 '\\((' << STRINGREGEX_ESCAPED_CHAR << '|[^)\\x00])*\\))')
    REGEX_LINKLABEL             = /\A\[(?:[^\\\[\]]|\\[\[\]]){0,1000}\]/
    REGEX_TICKSHERE             = /^`+/
    REGEX_TICKS                 = /`+/
    REGEX_EMAILAUTOLINK         = /^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>/
    REGEX_AUTOLINK              = /^<(?:coap|doi|javascript|aaa|aaas|about|acap|cap|cid|crid|data|dav|dict|dns|file|ftp|geo|go|gopher|h323|http|https|iax|icap|im|imap|info|ipp|iris|iris.beep|iris.xpc|iris.xpcs|iris.lwz|ldap|mailto|mid|msrp|msrps|mtqp|mupdate|news|nfs|ni|nih|nntp|opaquelocktoken|pop|pres|rtsp|service|session|shttp|sieve|sip|sips|sms|snmp|soap.beep|soap.beeps|tag|tel|telnet|tftp|thismessage|tn3270|tip|tv|urn|vemmi|ws|wss|xcon|xcon-userid|xmlrpc.beep|xmlrpc.beeps|xmpp|z39.50r|z39.50s|adiumxtra|afp|afs|aim|apt|attachment|aw|beshare|bitcoin|bolo|callto|chrome|chrome-extension|com-eventbrite-attendee|content|cvs|dlna-playsingle|dlna-playcontainer|dtn|dvb|ed2k|facetime|feed|finger|fish|gg|git|gizmoproject|gtalk|hcp|icon|ipn|irc|irc6|ircs|itms|jar|jms|keyparc|lastfm|ldaps|magnet|maps|market|message|mms|ms-help|msnim|mumble|mvn|notes|oid|palm|paparazzi|platform|proxy|psyc|query|res|resource|rmi|rsync|rtmp|secondlife|sftp|sgn|skype|smb|soldat|spotify|ssh|steam|svn|teamspeak|things|udp|unreal|ut2004|ventrilo|view-source|webcal|wtai|wyciwyg|xfire|xri|ymsgr):[^<>\x00-\x20]*>/i
    REGEX_HTMLTAG               = Regexp.new('^' << STRINGREGEX_HTMLTAG)
    REGEX_FINALSPACE            = / *$/
    REGEX_MAIN                  = /^[^\n`\[\]\\!<&*_'"]+/

    REGEX_HTMLOPENS             = [
        /^<(?:script|pre|style)(?:\s|>|$)/i,
        /<!--/,
        /^<[?]/,
        /^<![A-Z]/,
        /^<!\[CDATA\[/,
        /^<[\/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|[\/]?[>]|$)/i,
        Regexp.new('^(?:' << STRINGREGEX_OPENTAG << '|' << STRINGREGEX_CLOSETAG << ')\s*$')
    ]

    REGEX_HTMLCLOSES            = [
        /<\/(?:script|pre|style)>/i,
        /-->/,
        /\?>/,
        />/,
        /\]\]>/
    ]

    REGEX_CODEFENCE             = /^`{3,}(?!.*`)|^~{3,}(?!.*~)/
    REGEX_INDENTEDCODE          = /^\s{4,}(.*)/
    REGEX_HORIZONTALRULE        = /^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/
    REGEX_HEADERATX             = /^\#{1,6}(?: +|$)/
    REGEX_HEADERSETEXT          = /^(?:=+|-+) *$/
    REGEX_LISTBULLET            = /^[*+-]( +|$)/
    REGEX_LISTORDERED           = /^(\d+)([.)])( +|$)/
    REGEX_SPACEATEOL            = /^ *(?:\n|$)/

    REGEX_BSLASHORAMPERSAND     = /[\\&]/
    REGEX_ENTORESCAPEDCHAR      = /\\#{STRINGREGEX_ESCAPABLE}|#{REGEX_ENTITY}/i

    def unescape_string(str)
      if REGEX_BSLASHORAMPERSAND.match(str)
        str.gsub(REGEX_ENTORESCAPEDCHAR) { |m|
          if m[0].ord == 92
            m[1]
          else
            CGI::unescapeHTML(m)
          end
        }
      else
        str
      end
    end
  end
end