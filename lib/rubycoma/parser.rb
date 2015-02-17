module RubyCoMa
  require_relative '../rubycoma/nodes'

  class Parser
    include Nodes

    attr_accessor :current_block
    attr_accessor :current_line
    attr_accessor :offset
    attr_accessor :indent
    attr_accessor :next_nonspace
    attr_accessor :current_line_blank
    attr_accessor :last_line_blank
    attr_accessor :doc
    attr_accessor :last_line_length

    CHARCODE_GREATERTHAN        = 62
    CHARCODE_SPACE              = 32
    CHARCODE_NEWLINE            = 10
    CHARCODE_LEFTSQUAREBRACKET  = 91

    REGEX_CODEFENCE             = /^`{3,}(?!.*`)|^~{3,}(?!.*~)/
    REGEX_INDENTEDCODE          = /^\s{4,}(.*)/
    REGEX_HORIZONTALRULE        = /^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/
    REGEX_HTML                  = Regexp.new(STRINGREGEX_HTMLOPEN, Regexp::IGNORECASE)
    REGEX_HEADERATX             = /^\#{1,6}(?: +|$)/
    REGEX_HEADERSETEXT          = /^(?:=+|-+) *$/
    REGEX_LISTBULLET            = /^[*+-]( +|$)/
    REGEX_LISTORDERED           = /^(\d+)([.)])( +|$)/

    STRINGREGEX_TAGNAMES        = '(?:article|header|aside|hgroup|iframe|blockquote|hr|body|li|map|button|object|canvas|ol|caption|output|col|p|colgroup|pre|dd|progress|div|section|dl|table|td|dt|tbody|embed|textarea|fieldset|tfoot|figcaption|th|figure|thead|footer|footer|tr|form|ul|h1|h2|h3|h4|h5|h6|video|script|style)'
    STRINGREGEX_HTMLOPEN        = '<(?:' << STRINGREGEX_TAGNAMES << '[\s/>]|/' << STRINGREGEX_TAGNAMES << '[\s>]|[?!])'

    @@helpers = {
        Document => {
            :continue => -> {true},
            :finalize => -> {},
            :start    => -> {false}
        },
        List => {
            :continue => -> {true},
            :finalize => -> {},
            :start    => -> {false}
        },
        ListItem => {
            :continue => -> (parser, node) {
              old_offset = parser.offset
              parser.offset = if parser.on_blank_line
                                parser.next_nonspace
                              elsif parser.indent >= node.marker_offset + node.padding
                                parser.offset += node.marker_offset + node.padding
                              else
                                parser.offset
                              end
              old_offset != parser.offset
            },
            :finalize => -> {},
            :start    => -> (parser) {false}
        },
        BlockQuote => {
            :continue => -> (parser) {
              ln = parser.current_line
              if (parser.indent <= 3 && parser.char_code_at(ln, parser.next_nonspace) == CHARCODE_GREATERTHAN)
                parser.offset = parser.next_nonspace + 1
                parser.offset += 1 unless parser.char_code_at(ln, parser.offset) != CHARCODE_SPACE
                return true
              end
              false
            },
            :finalize => -> {},
            :start    => -> (parser) {
              if parser.char_code_at(parser.current_line, parser.next_nonspace) == CHARCODE_GREATERTHAN
                parser.offset = parser.next_nonspace + 1
                parser.offset += 1 if parser.char_code_at(parser.current_line, parser.offset) == CHARCODE_SPACE
                parser.add_child(BlockQuote.new)
                return true
              end
              false
            }
        },
        Header => {
            :continue => -> {false},
            :finalize => -> {},
            :start    => -> (parser, container) {
              if container.class == Paragraph && container.lines.count == 1 && match = REGEX_HEADERSETEXT.match(parser.current_line[parser.next_nonspace..-1])
                level = match[0][0] == '=' ? 1 : 2
                h = Header.new(level)
                h.strings.push(container.strings[0])
                parent = container.parent
                parent.remove_child(container)
                parent.add_child(h)
                parser.offset = parser.current_line.length
                return true
              elsif match = REGEX_HEADERATX.match(parser.current_line[parser.next_nonspace..-1])
                parser.offset = parser.next_nonspace + match[0].length
                h = Header.new(match[0].strip.length)
                h.strings.push(parser.current_line[parser.offset..-1])
                parser.current_block.add_child(h)
                parser.offset = parser.current_line.length
                return true
              end
              false
            }
        },
        HorizontalRule => {
            :continue => -> {false},
            :finalize => -> {},
            :start    => -> (parser){
              if REGEX_HORIZONTALRULE.match(parser.current_line[parser.next_nonspace..-1])
                hr = HorizontalRule.new
                parser.add_child(parser.current_block, hr)
                parser.offset = parser.current_line.length
                return true
              end
              false
            }
        },
        Code => {
            :continue => -> (parser, node) {
              container = node
              ln = parser.current_line
              if container.is_fenced
                match = if parser.indent < 4 && ln[parser.next_nonspace] == container.fence_character
                          REGEX_CODEFENCE.match(ln[parser.next_nonspace..-1])
                        else
                          nil
                        end
                return false if match && match[0].length >= container.fence_length

                i = container.fence_offset
                while i > 0 && char_code_at(ln, @offset) == CHARCODE_SPACE
                  @offset += 1
                  i -= 1
                end
                return true
              end

              #indented code
              old_offset = parser.offset
              parser.offset = if parser.indent >= 4
                                parser.offset + 4
                              elsif parser.on_blank_line
                                parser.offset + parser.next_nonspace
                              else
                                parser.offset
                              end

              parser.offset != old_offset
            },
            :finalize => -> (parser, node) {},
            :start    => -> (parser) {
              if parser.indent >= 4
                if parser.current_block.class != Paragraph && !parser.on_blank_line
                  parser.offset += 4
                  cb = Code.new
                  cb.offset = parser.offset
                  parser.add_child(parser.current_block, cb)
                else
                  parser.offset = parser.next_nonspace
                end
                return true
              end

              if match = REGEX_CODEFENCE.match(parser.current_line[parser.next_nonspace..-1])
                cb = Code.new(true, match[0][0], match[0].length, parser.indent)
                parser.add_child(parser.current_block, cb)
                parser.offset = parser.next_nonspace + match[0].length
                return true
              end

              false
            }
        },
        HTML => {
            :continue => -> (parser) {
              !parser.on_blank_line
            },
            :finalize => -> (parser, node) {},
            :start    => -> (parser) {
              if REGEX_HTMLOPEN.match(parser.current_line[parser.next_nonspace..-1])
                b = HTML.new
                parser.add_child(@current_block, b)
              end
            }
        },
        Paragraph => {
            :continue => -> (parser) {
              !parser.on_blank_line
            },
            :finalize => -> {},
            :start    => -> {false}
        }
    }

    def initialize
      @doc = Document.new
      @current_block = @doc
      @current_line = nil
      @line_number = 0
      @offset = 0
      @indent = 0
      @next_nonspace = -1
      @current_line_blank = false
      @last_line_blank = false
      @last_line_length = 0
    end

    def parse_string(input)
      lines = input.lines.map(&:chomp)
      parse_lines(lines)
    end

    def parse_file(filename)
      abort("The file \"#{filename}\" couldn't be opened. Does it exist?") unless File.exists?(File.expand_path(filename))

      file = File.open(File.expand_path(filename))

      lines = file.readlines.map(&:chomp)
      parse_lines(lines)
    end

    def parse_lines(lines)
      lines.each_with_index { |line, index|
        @current_line = index
        @last_line_blank = @current_line_blank
        @current_line_blank = false
        incorporate_line(line)
      }
    end

    def incorporate_line(line)
      @current_line = expand_tabs(line)
      @offset = 0

      find_next_nonspace

      should_continue = @@helpers[@current_block.class][:continue].call(self, @current_block)

      # code block, easy peasy
      if should_continue && @current_block.accepts_lines? && @current_block.class != Paragraph
        add_line_to_node(@current_line, @current_block)
        return
      end

      if @last_line_blank && @current_line_blank
        return if close_all_lists(@current_block)
      end

      # if we shouldnt continue, back up until we find a container for our current line
      unless should_continue
        # close off fenced code if necessary
        if @current_block.class == Code && @current_block.is_fenced
          finalize_node(@current_block)
          return
        end

        finalize_node(@current_block) until @current_block <= Container || @current_block.class == Paragraph
      end

      # try all node starts, stopping when we've hit a leaf to add our line
      can_add_line = false
      line_finished = false
      until can_add_line || line_finished
        counter = 0
        @@helpers.each_value { |type|

          if type[:start].call(self)
            if @offset >= @current_line.length
              line_finished = true
            elsif @current_block <= Leaf
              can_add_line = true
            end
            break
          end
          counter += 1
        }
        if counter == @@helpers.count
          p = Paragraph.new
          add_child(@current_block, p)
          can_add_line = true
        end
      end

      add_line_to_node(@current_line, @current_block) if !line_finished
    end

    def finalize_node(node)
      node.open = false
      helpers[node.class][:finalize].call()
      @current_block = node.parent
    end

    def add_line_to_node(line, node)
      node.strings.push(line[@offset..-1]) if @offset < line.length
    end

    def expand_tabs(line)
      line.gsub(/([^\t]*)\t/) {$1 + ' ' * (4 - ($1.length % 4))}
    end

    def close_all_lists(node)
      b = node
      tree_changed = false
      while b.class == ListItem && b.class == List
        finalize_node(b)
        tree_changed = true
        b = b.parent
      end
      @current_block = b
      tree_changed
    end

    def find_next_nonspace
      line = @current_line
      match = /[^ \t\n]/.match(line[@offset..-1])
      if match.nil?
        @next_nonspace = line.length
        @current_line_blank = true
      else
        @next_nonspace = @offset + match.begin(0)
        @current_line_blank = false
      end
      @indent = @next_nonspace - @offset
    end

    def char_code_at(line, position)
      return -1 unless position < line.length
      line[position].ord
    end

    def add_child(parent, child)
      container = parent
      until container.can_contain?(child)  # go up until we find a container
        finalize_node(container)
        container = container.parent
      end
      container.add_child(child)
      @current_block = child
    end

    # def parse_list(first_line, parent_block)
    #
    #   list_type = if (match = /(^\s*[+\-*] +)/.match(first_line))
    #                 :unordered
    #               elsif (match = /(^\s*(\d+)\. +)/.match(first_line))
    #                 :ordered
    #               else
    #                 nil
    #               end
    #
    #   return nil if list_type.nil?
    #
    #   if parent_block.type == :document
    #     list_block = Block.new(:list)
    #     list_block.info[:list_type] = list_type
    #
    #     if list_type == :ordered
    #       list_block.info[:start_number] = match.captures[1]
    #     end
    #   end
    #
    #   if parent_block.type == :list_item
    #
    #   end
    #
    #   first_line.slice!(0..(match.captures[0].length-1))
    #
    #   list_item_block = Block.new(:list_item)
    #   list_item_block.info[:indent] = match.captures[0].length
    #   list_block.add_child(list_item_block)
    #
    #   #parse_for_parent(list_item_block)
    #
    #   #parent_block.add_child(list_block)
    #   nil
    # end
    #
    # def parse_paragraph(first_line, parent_block)
    #   if setext = parse_setext(first_line, parent_block)
    #     return setext
    #   end
    #
    #   if parent_block.type == :list_item
    #     if line_indent = /(^\s+)/.match(first_line)
    #       return nil unless line_indent.captures[0].length == parent_block.info[:indent]
    #       parent_block.parent.info[:is_tight] = false
    #     end
    #   end
    #
    #   p_block = Block.new(:paragraph)
    #   p_block.lines.push(first_line)
    #   @current_index += 1
    #   while @current_index < @lines.length
    #     new_line = @lines[@current_index]
    #     break if /^\s*(?:[+\-*]|\d+\.) +/.match(new_line) #list interrupt
    #
    #     break if new_line.strip.empty?
    #     p_block.lines.push(new_line)
    #     @current_index += 1
    #   end
    #   parent_block.add_child(p_block)
    #   p_block
    # end
    #
    # def parse_setext(first_line, parent_block)
    #   next_line = @lines[@current_index + 1]
    #   setext_match = /^\s{,3}(?:=+|-+) *$/.match(next_line)
    #   return nil if setext_match.nil?
    #
    #   setext_block = Block.new(:header)
    #   setext_block.lines.push(first_line)
    #   parent_block.add_child(setext_block)
    #   @current_index += 2
    #   setext_block
    # end
    #
    # def parse_atx(first_line, parent_block)
    #   atx_match = /^\s{,3}(\#{1,6}) (.*)/.match(first_line)
    #   return nil if atx_match.nil?
    #
    #   content = atx_match.captures[1]
    #   atx_block = Block.new(:header)
    #   atx_block.info[:header_level] = atx_match.captures[0].length
    #   atx_block.lines.push(content) unless content.nil?
    #   parent_block.add_child(atx_block)
    #   @current_index += 1
    #   atx_block
    # end
    #
    # def parse_indented_code(first_line, parent_block)
    #   match = RE_INDENTED_CODE.match(first_line)
    #   return nil if match.nil?
    #
    #   code_block = Block.new(:indented_code)
    #   code_block.lines.push(match.captures[0][4..-1])
    #
    #   @current_index += 1
    #   while @current_index < @lines.length
    #     next_line = @lines[@current_index]
    #
    #     if next_line.length == 0
    #       content = next_line
    #     else
    #       indented_code_match = /^\s{4,}(.*)/.match(next_line)
    #       break if indented_code_match.nil?
    #       content = indented_code_match.captures[0][4..-1]
    #     end
    #
    #     code_block.lines.push(content)
    #     @current_index += 1
    #   end
    #
    #   parent_block.add_child(code_block)
    #   code_block
    # end
    #
    # def parse_fenced_code(first_line, parent_block)
    #   match = /^\s*(~~~|```)(.*)/.match(first_line)
    #   return nil if match.nil?
    #
    #   fence_char = match.captures[0].chr
    #   code_block = Block.new(:fenced_code)
    #   unless match.captures[1].strip.empty?
    #     code_block.info[:fc_info] = match.captures[1].strip
    #   end
    #
    #   @current_index += 1
    #   while @current_index < @lines.length
    #     next_line = @lines[@current_index]
    #     @current_index += 1
    #     break if /#{fence_char}{3,}(?:\s*$)/.match(next_line)
    #     code_block.lines.push(next_line)
    #   end
    #
    #   parent_block.add_child(code_block)
    #   code_block
    # end
    #
    # def parse_horizontal_rule(first_line, parent_block)
    #   match = /^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/.match(first_line)
    #   return nil if match.nil?
    #
    #   horule_block = Block.new(:horizontal_rule)
    #   parent_block.add_child(horule_block)
    #   @current_index += 1
    #   horule_block
    # end
  end
end