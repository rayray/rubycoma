module RubyCoMa
  require_relative '../rubycoma/nodes'
  class InlineParser
    include Nodes
    require 'cgi'

    attr_accessor :line_index
    attr_accessor :char_index
    attr_accessor :node
    attr_accessor :delimiters

    CHARCODE_AMPERSAND      = 38
    CHARCODE_ASTERISK       = 42
    CHARCODE_BACKSLASH      = 92
    CHARCODE_BACKTICK       = 96
    CHARCODE_RIGHTPAREN     = 41
    CHARCODE_RIGHTBRACKET   = 93
    CHARCODE_COLON          = 58
    CHARCODE_LEFTBRACKET    = 91
    CHARCODE_LEFTPAREN      = 40
    CHARCODE_EXCLAM         = 33
    CHARCODE_LESSTHAN       = 60
    CHARCODE_UNDERSCORE     = 95
    CHARCODE_NEWLINE        = 10
    CHARCODE_SINGLEQUOTE    = 39
    CHARCODE_DOUBLEQUOTE    = 34

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
    REGEX_LINKDEST              = Regexp.new('^(?:' << STRINGREGEX_REG_CHAR << '+|' << STRINGREGEX_ESCAPED_CHAR << '|' << STRINGREGEX_IN_PARENS_NOSP << ')*')
    REGEX_LINKTITLE             = Regexp.new('^(?:"(' << STRINGREGEX_ESCAPED_CHAR << '|[^"\\x00])*"' <<
                                             '|' <<
                                             '\'(' << STRINGREGEX_ESCAPED_CHAR << '|[^\'\\x00])*\'' <<
                                             '|' <<
                                             '\\((' << STRINGREGEX_ESCAPED_CHAR << '|[^)\\x00])*\\))')
    REGEX_LINKLABEL             = /^\[(?:[^\\\[\]]|\\[\[\]]){0,1000}\]/
    REGEX_TICKSHERE             = /^`+/
    REGEX_TICKS                 = /`+/
    REGEX_EMAILAUTOLINK         = /^<([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>/
    REGEX_AUTOLINK              = /^<(?:coap|doi|javascript|aaa|aaas|about|acap|cap|cid|crid|data|dav|dict|dns|file|ftp|geo|go|gopher|h323|http|https|iax|icap|im|imap|info|ipp|iris|iris.beep|iris.xpc|iris.xpcs|iris.lwz|ldap|mailto|mid|msrp|msrps|mtqp|mupdate|news|nfs|ni|nih|nntp|opaquelocktoken|pop|pres|rtsp|service|session|shttp|sieve|sip|sips|sms|snmp|soap.beep|soap.beeps|tag|tel|telnet|tftp|thismessage|tn3270|tip|tv|urn|vemmi|ws|wss|xcon|xcon-userid|xmlrpc.beep|xmlrpc.beeps|xmpp|z39.50r|z39.50s|adiumxtra|afp|afs|aim|apt|attachment|aw|beshare|bitcoin|bolo|callto|chrome|chrome-extension|com-eventbrite-attendee|content|cvs|dlna-playsingle|dlna-playcontainer|dtn|dvb|ed2k|facetime|feed|finger|fish|gg|git|gizmoproject|gtalk|hcp|icon|ipn|irc|irc6|ircs|itms|jar|jms|keyparc|lastfm|ldaps|magnet|maps|market|message|mms|ms-help|msnim|mumble|mvn|notes|oid|palm|paparazzi|platform|proxy|psyc|query|res|resource|rmi|rsync|rtmp|secondlife|sftp|sgn|skype|smb|soldat|spotify|ssh|steam|svn|teamspeak|things|udp|unreal|ut2004|ventrilo|view-source|webcal|wtai|wyciwyg|xfire|xri|ymsgr):[^<>\x00-\x20]*>/i
    REGEX_HTMLTAG               = Regexp.new('^' << STRINGREGEX_HTMLTAG)
    REGEX_FINALSPACE            = / *$/
    REGEX_MAIN                  = /^[^\n`\[\]\\!<&*_'"]+/

    def initialize
      @delimiters = nil
    end

    def peek
      if @char_index < @string.length
        return @string[@char_index].ord
      end
      -1
    end

    # if a match is found, advance the current char position
    def match(re)
      m = re.match(@string[@char_index..-1])
      if m
        @char_index += m.begin(0) + m[0].length
        return m[0]
      end
      nil
    end

    def spnl
      match(REGEX_SPACES)
      if peek == CHARCODE_NEWLINE
        match(REGEX_SPACES)
      end
      true
    end

    def add_inline(type, string = nil)
      inl = Inline.new(type, string)
      @node.add_child(inl)
      inl
    end

    def parse_node(node)
      @node = node
      @string = node.strings.join("\n")
      @char_index = 0
      c = peek
      until c == -1
        inline_added = case c
                         when CHARCODE_NEWLINE
                           handle_newline
                         when CHARCODE_AMPERSAND
                           parse_entity
                         when CHARCODE_ASTERISK || CHARCODE_UNDERSCORE
                           handle_delimiters(c)
                         when CHARCODE_BACKSLASH
                           parse_backslash
                         when CHARCODE_BACKTICK
                           parse_backticks
                         when CHARCODE_EXCLAM
                           parse_exclam
                         when CHARCODE_LEFTBRACKET
                           parse_left_bracket
                         when CHARCODE_RIGHTBRACKET
                           parse_right_bracket
                         when CHARCODE_LESSTHAN
                           parse_less_than
                         else
                           parse_string
                       end

        unless inline_added
          @char_index += 1
          add_inline(:text, char_from_ord(c))
        end
        c = peek
      end
      process_emphasis
    end

    def handle_newline
      @char_index += 1
      lastc = @node.last_child
      if lastc && lastc.style == :text
        sps = REGEX_FINALSPACE.match(lastc.content)[0].length
        add_inline(sps >= 2 ? :hardbreak : :softbreak)
      else
        add_inline(:softbreak)
      end
      true
    end

    def parse_left_bracket
      start_pos = @char_index
      @char_index += 1

      node = Inline.new(:text, '[')
      @node.add_child(node)

      add_delimiter({:cc => CHARCODE_LEFTBRACKET,
                     :num_delims => 1,
                     :node => node,
                     :can_open => true,
                     :can_close => false,
                     :index => start_pos,
                     :active => true
                    })
      true
    end

    def parse_exclam
      start_pos = @char_index
      @char_index += 1
      if peek == CHARCODE_LEFTBRACKET
        @char_index += 1

        node = Inline.new(:text, '![')
        @node.add_child(node)

        add_delimiter({:cc => CHARCODE_EXCLAM,
                       :num_delims => 1,
                       :node => node,
                       :can_open => true,
                       :can_close => false,
                       :index => start_pos + 1,
                       :active => true
                      })
      else
        add_inline(:text, '!')
      end
      true
    end

    def parse_backslash
      @char_index += 1
      if peek == CHARCODE_NEWLINE
        @char_index += 1
        add_inline(:hardbreak)
      elsif REGEX_ESCAPABLE.match(@string[@char_index])
        add_inline(:text, @string[@char_index])
      else
        add_inline(:text, '\\')
      end
      true
    end

    def parse_backticks
      ticks = match(REGEX_TICKSHERE)
      return false if ticks.nil?
      after_open_ticks = @char_index
      matched = match(REGEX_TICKS)
      until matched.nil?
        if matched == ticks
          add_inline(:code_inline, @string[after_open_ticks..(@char_index - ticks.length)-1])
          return true
        end
      end

      @char_index = after_open_ticks
      add_inline(:text, ticks)
      true
    end

    def parse_autolink
      if m = match(REGEX_EMAILAUTOLINK)
        dest = m[1..-1]
        inl = Inline.new(:link)
        inl.destination = 'mailto:' << dest
        inl.title = ''
        inl.add_child(Inline.new(:text, dest))
        @node.add_child(inl)
        return true
      end

      if m = match(REGEX_AUTOLINK)
        dest = m[1..-1]
        inl = Inline.new(:link)
        inl.destination = dest
        inl.title = ''
        inl.add_child(Inline.new(:text, dest))
        @node.add_child(inl)
        return true
      end
      false
    end

    def parse_less_than
      m = match(REGEX_HTMLTAG)
      return false if m.nil?
      add_inline(:html, m)
      true
    end

    def parse_link_destination
      res = match(REGEX_LINKDESTBRACES)
      if res.nil?
        res = match(REGEX_LINKDEST)
        return nil if res.nil?
        return CGI::escape(res)
      end
      CGI::escape(res[1..-2])
    end

    def parse_link_title
      title = match(REGEX_LINKTITLE)
      return nil if title.nil?
      title[1..-2]
    end

    def parse_link_label
      m = match(REGEX_LINKLABEL)
      return 0 if m.nil?
      m.length
    end

    def parse_right_bracket
      @char_index += 1
      start_pos = @char_index

      opener = @delimiters

      until opener.nil?
        if opener[:cc] == CHARCODE_LEFTBRACKET || opener[:cc] == CHARCODE_EXCLAM
          break
        end
        opener = opener[:previous]
      end

      if opener.nil?
        add_inline(:text, "]")
        return true
      end

      unless opener[:active]
        add_inline(:text, "]")
        remove_delimiter(opener)
        return true
      end

      is_image = opener[:cc] == CHARCODE_EXCLAM
      matched = false
      title = ""
      dest = ""
      reflabel = ""

      if peek == CHARCODE_LEFTPAREN
        @char_index += 1

        if spnl &&
            (dest = parse_link_destination) &&
            spnl &&
            REGEX_WHITESPACECHARACTER.match(@string[@char_index - 1]) &&
            ((title = parse_link_title) || true) &&
            spnl &&
            peek == CHARCODE_RIGHTPAREN
          @char_index += 1
          matched = true
        end
      else
        savepos = @char_index
        spnl
        before_label = @char_index
        n = parse_link_label
        reflabel = if n == 0 || n == 2
                     @string[opener[:index]..start_pos]
                   else
                     @string[before_label..before_label+n-1]
                   end
        @char_index = savepos if n == 0
        #TODO implement reference map
      end

      if matched
        inl = Inline.new(is_image ? :image : :link)
        inl.destination = dest
        inl.title = title

        tmp = opener[:inline_node].next
        until tmp.nil?
          nxt = tmp.next
          @node.remove_child(tmp)
          inl.add_child(tmp)
          tmp = nxt
        end

        add_inline(inl)
        process_emphasis(opener[:previous])
        @node.remove_child(opener[:inline_node])

        unless is_image
          opener = @delimiters
          until opener.nil?
            if opener[:cc] == CHARCODE_LEFTBRACKET
              opener[:active] = false
            end
            opener = opener[:previous]
          end
        end
      else
        remove_delimiter(opener)
        @char_index = start_pos
        add_inline(:text, ']')
      end
      true
    end

    def parse_entity
      if string = match(REGEX_ENTITY)
        add_inline(:text, string)
      end
      false
    end

    def handle_delimiters(cc)
      num_delims, can_open, can_close = scan_delimiters(cc)

      return false if num_delims.nil?
      start_pos = @char_index
      @char_index += num_delims
      contents = if cc == CHARCODE_SINGLEQUOTE
                   "\u2019"
                 elsif cc == CHARCODE_DOUBLEQUOTE
                   "\u201C"
                 else
                   @string[start_pos..@char_index-1]
                 end

      inl = add_inline(:text, contents)

      add_delimiter({:cc => cc,
                     :num_delims => num_delims,
                     :inline_node => inl,
                     :can_open => can_open,
                     :can_close => can_close,
                     :active => true
                    })
      true
    end

    def parse_string
      if m = match(REGEX_MAIN)
        add_inline(:text, m)
        return true
      end
      false
    end

    def char_from_ord(ord)
      [ord].pack('U')
    end

    def add_delimiter(d)
      d[:previous] = @delimiters
      @delimiters[:next] = d unless @delimiters.nil?
      @delimiters = d
    end

    def remove_delimiter(d)
      unless d[:previous].nil?
        d[:previous][:next] = d[:next]
      end
      if d[:next].nil?
        @delimiters = d[:previous]
      else
        d[:next][:previous] = d[:previous]
      end
    end

    def scan_delimiters(cc)
      num_delims = 0
      start_pos = @char_index

      can_open = false
      can_close = false

      if cc == CHARCODE_SINGLEQUOTE || cc == CHARCODE_DOUBLEQUOTE
        num_delims += 1
        @char_index += 1
      else
        while peek == cc
          num_delims += 1
          @char_index += 1
        end
      end

      return nil, nil, nil if num_delims == 0

      char_before = start_pos == 0 ? "\n" : @string[@char_index-1]

      cc_after = peek
      char_after = if cc_after == -1
                     "\n"
                   else
                     char_from_ord(cc_after)
                   end

      after_is_whitespace = char_after =~ REGEX_WHITESPACECHARACTER
      after_is_punc = char_after =~ REGEX_PUNCTUATION
      before_is_whitespace = char_before =~ REGEX_WHITESPACECHARACTER
      before_is_punc = char_before =~ REGEX_PUNCTUATION

      left_flanking = !after_is_whitespace && !(after_is_punc && !before_is_whitespace && !before_is_punc)
      right_flanking = !before_is_whitespace && !(before_is_punc && !after_is_whitespace && !after_is_punc)

      if cc == CHARCODE_UNDERSCORE
        can_open = left_flanking && (!right_flanking || before_is_punc)
        can_close = right_flanking && (!left_flanking || after_is_punc)
      elsif cc == CHARCODE_DOUBLEQUOTE || cc == CHARCODE_SINGLEQUOTE
        can_open = left_flanking && !right_flanking
        can_close = right_flanking
      else
        can_open = left_flanking
        can_close = right_flanking
      end
      @char_index = start_pos
      return num_delims, can_open, can_close
    end

    def process_emphasis(stack_bottom = nil)

      openers_bottom = { CHARCODE_UNDERSCORE => stack_bottom,
                         CHARCODE_ASTERISK => stack_bottom,
                         CHARCODE_SINGLEQUOTE => stack_bottom,
                         CHARCODE_DOUBLEQUOTE => stack_bottom }

      closer = @delimiters
      until closer.nil? || closer[:previous] == stack_bottom
        closer = closer[:previous]
      end
      until closer.nil?
        closercc = closer[:cc]
        if closer[:can_close] &&
            (closercc == CHARCODE_ASTERISK ||
                closercc == CHARCODE_UNDERSCORE ||
                closercc == CHARCODE_DOUBLEQUOTE ||
                closercc == CHARCODE_SINGLEQUOTE)

          opener = closer[:previous]
          opener_found = false

          until opener.nil? || opener == stack_bottom || opener == openers_bottom[closercc]
            if opener[:cc] == closer[:cc] && opener[:can_open]
              opener_found = true
              break
            end
            opener = opener[:previous]
          end

          old_closer = closer

          if closercc == CHARCODE_ASTERISK || CHARCODE_UNDERSCORE
            if opener_found

              use_delims = if closer[:num_delims] < 3 || opener[:num_delims] < 3
                             if closer[:num_delims] <= opener[:num_delims]
                               closer[:num_delims]
                             else
                               opener[:num_delims]
                             end
                           else
                             if closer[:num_delims] % 2 == 0
                               2
                             else
                               1
                             end
                           end
              opener_inl = opener[:node]
              closer_inl = closer[:node]

              opener[:num_delims] -= use_delims
              closer[:num_delims] -= use_delims

              opener_inl.content = opener_inl.content[0..(opener_inl.content.length - use_delims)-1]
              closer_inl.content = closer_inl.content[0..(closer_inl.content.length - use_delims)-1]

              emph = Inline.new(use_delims == 1 ? :emphasized : :strong)

              tmp = opener_inl[:next]
              until tmp.nil? || tmp == closer_inl
                nxt = tmp[:next]
                tmp.remove
                emph.add_child(tmp)
                tmp = nxt
              end

              opener_inl.insert(emph)

              #remove delims between opener & closer
              if opener[:next] != closer
                opener[:next] = closer
                closer[:previous] = opener
              end

              if opener[:num_delims] == 0
                opener_inl.remove
                remove_delimiter(opener)
              end

              if closer[:num_delims] == 0
                closer_inl.remove
                tempstack = closer[:next]
                remove_delimiter(closer)
                closer = tempstack
              end
            else
              closer = closer[:next]
            end
          elsif closercc == CHARCODE_SINGLEQUOTE
            closer.node.content = "\u2019"
            opener.node.content = "\u2018" if opener_found
            closer = closer[:next]
          elsif closercc == CHARCODE_DOUBLEQUOTE
            closer.node.content = "\u201D"
            opener.node.content = "\u201C" if opener_found
          end

          unless opener_found
            openers_bottom[closercc] = old_closer[:previous]
            remove_delimiter(old_closer) unless old_closer[:can_open]
          end
        else
          closer = closer[:next]
        end
      end

      until @delimiters.nil? || @delimiters == stack_bottom
        remove_delimiter(@delimiters)
      end
    end
  end
end