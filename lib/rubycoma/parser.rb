module RubyCoMa
  require_relative '../rubycoma/nodes'
  require_relative '../rubycoma/inline_parser'

  class Parser
    include Nodes

    attr_accessor :current_block
    attr_accessor :current_line
    attr_accessor :offset
    attr_accessor :indent
    attr_accessor :next_nonspace
    attr_accessor :on_blank_line
    attr_accessor :last_line_blank
    attr_accessor :doc
    attr_accessor :last_line_length

    CHARCODE_GREATERTHAN        = 62
    CHARCODE_SPACE              = 32
    CHARCODE_NEWLINE            = 10
    CHARCODE_LEFTSQUAREBRACKET  = 91

    STRINGREGEX_TAGNAMES        = '(?:article|header|aside|hgroup|iframe|blockquote|hr|body|li|map|button|object|canvas|ol|caption|output|col|p|colgroup|pre|dd|progress|div|section|dl|table|td|dt|tbody|embed|textarea|fieldset|tfoot|figcaption|th|figure|thead|footer|footer|tr|form|ul|h1|h2|h3|h4|h5|h6|video|script|style)'
    STRINGREGEX_HTMLOPEN        = '<(?:' << STRINGREGEX_TAGNAMES << '[\s/>]|/' << STRINGREGEX_TAGNAMES << '[\s>]|[?!])'

    REGEX_CODEFENCE             = /^`{3,}(?!.*`)|^~{3,}(?!.*~)/
    REGEX_INDENTEDCODE          = /^\s{4,}(.*)/
    REGEX_HORIZONTALRULE        = /^(?:(?:\* *){3,}|(?:_ *){3,}|(?:- *){3,}) *$/
    REGEX_HTMLOPEN              = Regexp.new(STRINGREGEX_HTMLOPEN, Regexp::IGNORECASE)
    REGEX_HEADERATX             = /^\#{1,6}(?: +|$)/
    REGEX_HEADERSETEXT          = /^(?:=+|-+) *$/
    REGEX_LISTBULLET            = /^[*+-]( +|$)/
    REGEX_LISTORDERED           = /^(\d+)([.)])( +|$)/

    @@helpers = {
        Document => {
            :continue => proc {true},
            :finalize => proc {},
            :start    => proc {false}
        },
        List => {
            :continue => proc {true},
            :finalize => proc { |parser, node|
              item = node.first_child
              until item.nil?
                if defined? item.strings && item.strings.last == '' && item.next
                  node.is_tight = false
                  break
                end

                subitem = item.first_child
                until subitem.nil?
                  if subitem.strings.last == '' && item.next && subitem.next
                    node.is_tight = false
                    break
                  end
                  subitem = subitem.next
                end
                item = item.next
              end
            },
            :start    => proc {false}
        },
        BlockQuote => {
            :continue => proc { |parser|
              ln = parser.current_line
              if (parser.indent <= 3 && parser.char_code_at(ln, parser.next_nonspace) == CHARCODE_GREATERTHAN)
                parser.offset = parser.next_nonspace + 1
                parser.offset += 1 unless parser.char_code_at(ln, parser.offset) != CHARCODE_SPACE
                next true
              end
              false
            },
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.char_code_at(parser.current_line, parser.next_nonspace) == CHARCODE_GREATERTHAN
                parser.offset = parser.next_nonspace + 1
                parser.offset += 1 if parser.char_code_at(parser.current_line, parser.offset) == CHARCODE_SPACE
                parser.add_child(parser.current_block, BlockQuote.new)
                next true
              end
              false
            }
        },
        Header => {
            :continue => proc {false},
            :finalize => proc {},
            :start    => proc { |parser|
              container = parser.current_block
              if container.class == Paragraph && container.strings.count == 1 && match = REGEX_HEADERSETEXT.match(parser.current_line[parser.next_nonspace..-1])
                level = match[0][0] == '=' ? 1 : 2
                h = Header.new(level)
                h.strings.push(container.strings[0])
                parent = container.parent
                parent.remove_child(container)
                parent.add_child(h)
                parser.current_block = h
                parser.offset = parser.current_line.length
                next true
              elsif match = REGEX_HEADERATX.match(parser.current_line[parser.next_nonspace..-1])
                parser.offset = parser.next_nonspace + match[0].length
                h = Header.new(match[0].strip.length)
                h.strings.push(parser.current_line[parser.offset..-1].gsub(/^ *#+ *$/, '').gsub(/ +#+ *$/, ''))
                parser.add_child(parser.current_block, h)
                parser.offset = parser.current_line.length
                next true
              end
              false
            }
        },
        HorizontalRule => {
            :continue => proc {false},
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.indent < 4 && REGEX_HORIZONTALRULE.match(parser.current_line[parser.next_nonspace..-1])
                hr = HorizontalRule.new
                parser.add_child(parser.current_block, hr)
                parser.offset = parser.current_line.length
                next true
              end
              false
            }
        },
        ListItem => {
            :continue => proc { |parser, node|
              old_offset = parser.offset
              parser.offset = if parser.on_blank_line
                                parser.next_nonspace
                              elsif parser.indent >= node.marker_offset + node.padding
                                parser.offset + node.marker_offset + node.padding
                              else
                                parser.offset
                              end
              old_offset != parser.offset
            },
            :finalize => proc {},
            :start    => proc { |parser|
              ln = parser.current_line[parser.next_nonspace..-1]
              list_node = nil
              spaces_after_marker = 0
              if match = REGEX_LISTBULLET.match(ln)
                list_node = ListItem.new(false)
                list_node.marker_character = match[0][0]
                spaces_after_marker = match[1].length
              elsif match = REGEX_LISTORDERED.match(ln)
                list_node = ListItem.new(true)
                list_node.start = Integer(match[1])
                list_node.delimiter = match[2]
                spaces_after_marker = match[3].length
              else
                next false
              end

              list_node.padding = match[0].length
              unless spaces_after_marker.between?(1, 4) && match[0].length != ln.length
                list_node.padding -= (spaces_after_marker + 1)
              end
              list_node.marker_offset = parser.indent
              parser.offset = parser.next_nonspace + list_node.padding

              # while (parser.current_block.class == Paragraph) ||
              #     (parser.current_block.class == ListItem && list_node.marker_offset < parser.current_block.padding) ||
              #     (parser.current_block.class == List && list_node.marker_offset < parser.current_block.marker_offset)
              #   parser.finalize_node(parser.current_block)
              # end

              if parser.current_block.class != List || !parser.current_block.matches?(list_node)
                parser.add_child(parser.current_block, List.new(list_node.is_ordered))
                parser.current_block.copy_properties(list_node)
              end
              parser.add_child(parser.current_block, list_node)
              true
            }
        },
        Code => {
            :continue => proc { |parser, node|
              container = node
              ln = parser.current_line
              if container.is_fenced
                match = if parser.indent < 4 && ln[parser.next_nonspace] == container.fence_character
                          REGEX_CODEFENCE.match(ln[parser.next_nonspace..-1])
                        else
                          nil
                        end
                next false if match && match[0].length >= container.fence_length

                i = container.fence_offset
                while i > 0 && parser.char_code_at(ln, parser.offset) == CHARCODE_SPACE
                  parser.offset += 1
                  i -= 1
                end
                next true
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
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.indent >= 4
                if parser.current_block.class != Paragraph && !parser.on_blank_line
                  parser.offset += 4
                  cb = Code.new
                  parser.add_child(parser.current_block, cb)
                else
                  parser.offset = parser.next_nonspace
                end
                next true
              end

              if match = REGEX_CODEFENCE.match(parser.current_line[parser.next_nonspace..-1])
                cb = Code.new(true, match[0][0], match[0].length, parser.indent)
                parser.add_child(parser.current_block, cb)
                parser.offset = parser.next_nonspace + match[0].length

                if parser.offset < parser.current_line.length && info = parser.current_line[parser.offset..-1].strip
                  cb.info_string = info if info.length > 0
                  parser.offset = parser.current_line.length
                end

                next true
              end

              false
            }
        },
        HTML => {
            :continue => proc { |parser|
              !parser.on_blank_line
            },
            :finalize => proc {},
            :start    => proc { |parser|
              if REGEX_HTMLOPEN.match(parser.current_line[parser.next_nonspace..-1])
                b = HTML.new
                parser.add_child(parser.current_block, b)
                next true
              end
              false
            }
        },
        Paragraph => {
            :continue => proc { |parser|
              !parser.on_blank_line
            },
            :finalize => proc {
              # jgm looks for link refs here
            },
            :start    => proc {false}
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
      @on_blank_line = false
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
        @last_line_blank = @on_blank_line
        @on_blank_line = false
        incorporate_line(line)
      }
      until @current_block.nil?
        finalize_node(@current_block)
      end
      parse_inlines(@doc)
      puts @doc.to_s
      @doc
    end

    def parse_inlines(block)
      iparser = InlineParser.new
      walker = NodeWalker.new(block)
      current = walker.current

      until current.nil?
        nodetype = current.class
        if !walker.entering && (nodetype == Paragraph || nodetype == Header)
          iparser.parse_node(current)
        end
        current = walker.next
      end
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

      if @on_blank_line
        return if @last_line_blank && close_all_lists(@current_block)
      end

      unless should_continue
        # close off fenced code or broken paragraph if necessary
        if (@current_block.class == Code && @current_block.is_fenced) || @current_block.class == Paragraph
          finalize_node(@current_block)
          return
        end
        finalize_node(@current_block)
      end

      # try all node starts, stopping when we've hit a leaf to add our line
      can_add_line = false
      line_finished = false
      until can_add_line
        counter = 0
        @@helpers.each_value { |type|
          if type[:start].call(self)
            if @offset >= @current_line.length
              line_finished = true
            elsif @current_block.class <= Leaf
              can_add_line = true
            else
              find_next_nonspace
            end
            break
          end
          counter += 1
        }
        return if line_finished
        if counter == @@helpers.count
          return if @on_blank_line
          unless @current_block.class == Paragraph
            p = Paragraph.new
            add_child(@current_block, p)
          end
          can_add_line = true
        end
      end

      add_line_to_node(@current_line, @current_block)
    end

    def finalize_node(node)
      node.open = false
      @@helpers[node.class][:finalize].call(self, node)
      @current_block = node.parent
    end

    def add_line_to_node(line, node)
      if @offset >= line.length
        node.strings.push("")
      else
        node.strings.push(line[@offset..-1])
      end
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
      #puts "line len #{line.length} and line is #{line} and offset is #{@offset} and match is #{match} and doc is #{@doc}"
      if match.nil?
        @next_nonspace = line.length
        @on_blank_line = true
      else
        @next_nonspace = @offset + match.begin(0)
        @on_blank_line = false
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
      @current_block
    end
  end
end