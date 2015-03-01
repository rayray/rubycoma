module RubyCoMa
  require_relative '../rubycoma/nodes'
  class InlineParser
    include Nodes

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

    REGEX_NONSPECIALCHARS   = /^[^\n`\[\]\\!<&*_]+/m
    REGEX_ENTITY            = /^&(?:#x[a-f0-9]{1,8}|#[0-9]{1,8}|[a-z][a-z0-9]{1,31});/
    REGEX_WHITESPACECHARACTER  = /^\s/
    REGEX_WHITESPACE     = /^\s+/
    REGEX_PUNCTUATION       = /^[\u2000-\u206F\u2E00-\u2E7F\\'!"#\$%&\(\)\*\+,\-\.\/:;<=>\?@\[\]\^_`\{\|\}~]/

    def initialize
      @char_index = 0
      @line_index = 0
      @delimiters = Array.new
    end

    def peek
      unless @char_index < @node.strings[@line_index].length
        @line_index += 1
        return -1 if @line_index == @node.strings.count
        @char_index = 0
        return CHARCODE_NEWLINE
      end
      @node[@line_index][@char_index].ord
    end

    # if a match is found, advance the current char position
    def match(re)
      m = re.match(@node.strings[@line_index][@char_index..-1])
      if m
        @char_index += m.begin(0) + m[0].length
        return m[0]
      end
      nil
    end

    def add_inline(type, string)
      inl = Inline.new(type, string)
      @node.inlines.push(inl)
      inl
    end

    def parse_node(node)
      @node = node
      c = peek
      until c == -1
        inline_added = case c
                         when CHARCODE_NEWLINE
                           handle_newline
                         when CHARCODE_AMPERSAND
                           parse_entity
                         when CHARCODE_ASTERISK || CHARCODE_UNDERSCORE
                           parse_emphasis(c)
                         when CHARCODE_BACKSLASH
                         when CHARCODE_BACKTICK
                         when CHARCODE_COLON
                         when CHARCODE_EXCLAM
                         when CHARCODE_LEFTBRACKET
                         when CHARCODE_RIGHTBRACKET
                         when CHARCODE_LESSTHAN
                         else
                           parse_string
                       end

        unless inline_added
          @char_index += 1
          add_inline(:text, char_from_ord(c))
        end
        c = peek
      end
    end

    def handle_newline
      true
    end

    def parse_entity
      if string = match(REGEX_ENTITY)
        add_inline(:text, string)
      end
      false
    end

    def parse_emphasis(cc)
      numdelims, can_open, can_close = scan_delimiters(cc)
      return false if numdelims == 0
      startpos = @char_index
      @char_index += numdelims
      inl = add_inline(:text, @node[@line_index][startpos..@char_index])
      @delimiters.push({:cc => cc,
                       :numdelims => numdelims,
                       :inline_node => inl,
                       :can_open => can_open,
                       :can_close => can_close,
                       :active => true})
      true
    end

    def parse_string
      false
    end

    def char_from_ord(ord)
      [ord].pack('U')
    end

    def scan_delimiters(cc)
      numdelims = 0
      startpos = @char_index
      char_before = startpos == 0 ? "\n" : @node.strings[@line_index][@char_index-1]
      can_open = can_close = false
      while peek == cc
        numdelims += 1
        @char_index += 1
      end
      cc_after = peek
      char_after = if cc_after == -1
                     "\n"
                   else
                     char_from_ord(cc_after)
                   end

      left_flanking = numdelims > 0 &&
          !REGEX_WHITESPACECHARACTER.match(char_after) &&
          !(REGEX_PUNCTUATION.match(char_after) &&
              !REGEX_WHITESPACECHARACTER.match(char_before) &&
              !REGEX_PUNCTUATION.match(char_before))
      right_flanking = numdelims > 0 &&
          !REGEX_WHITESPACECHARACTER.match(char_before) &&
          !(REGEX_PUNCTUATION.match(char_before) &&
              !REGEX_WHITESPACECHARACTER.match(char_after) &&
              !REGEX_PUNCTUATION.match(char_after))
      if cc == CHARCODE_UNDERSCORE
        can_open = left_flanking && !right_flanking
        can_close = right_flanking && !left_flanking
      else
        can_open = left_flanking
        can_close = right_flanking
      end
      @char_index = startpos
      return numdelims, can_open, can_close
    end
  end
end