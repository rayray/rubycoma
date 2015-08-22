module RubyCoMa
  require_relative '../rubycoma/nodes'
  require_relative '../rubycoma/inline_parser'

  class Parser
    include Nodes

    attr_accessor :current_block
    attr_accessor :current_line
    attr_accessor :offset
    attr_accessor :column
    attr_accessor :indent
    attr_accessor :next_nonspace
    attr_accessor :next_nonspace_column
    attr_accessor :on_blank_line
    attr_accessor :last_line_blank
    attr_accessor :doc
    attr_accessor :last_line_length

    CHARCODE_GREATERTHAN        = 62
    CHARCODE_SPACE              = 32
    CHARCODE_TAB                = 9
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
                if parser.ends_with_blank_line(item) && item.next
                  node.is_tight = false
                  break
                end

                subitem = item.first_child
                until subitem.nil?
                  if parser.ends_with_blank_line(item) && (item.next || subitem.next)
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
                parser.move_to_next_nonspace
                parser.move_offset(1)
                cc = parser.char_code_at(ln, parser.offset)
                parser.move_offset(1) if cc == CHARCODE_SPACE || cc == CHARCODE_TAB
                next true
              end
              false
            },
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.char_code_at(parser.current_line, parser.next_nonspace) == CHARCODE_GREATERTHAN
                parser.move_to_next_nonspace
                parser.move_offset(1)
                cc = parser.char_code_at(parser.current_line, parser.offset)
                parser.move_offset(1) if cc == CHARCODE_SPACE || cc == CHARCODE_TAB
                parser.add_child(BlockQuote.new)
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
              if parser.indent < 4 &&
                  container.class == Paragraph &&
                  container.strings.count == 1 &&
                  match = REGEX_HEADERSETEXT.match(parser.current_line[parser.next_nonspace..-1])
                level = match[0][0] == '=' ? 1 : 2
                h = Header.new(level)
                h.strings.push(container.strings[0])
                parent = container.parent
                container.remove
                parent.add_child(h)
                parser.current_block = h
                parser.move_offset(parser.current_line.length - parser.offset)
                next true
              elsif parser.indent < 4 &&
                  match = REGEX_HEADERATX.match(parser.current_line[parser.next_nonspace..-1])
                parser.move_to_next_nonspace
                parser.move_offset(match[0].length)
                h = Header.new(match[0].strip.length)
                h.strings.push(parser.current_line[parser.offset..-1].gsub(/^ *#+ *$/, '').gsub(/ +#+ *$/, ''))
                parser.add_child(h)
                parser.move_offset(parser.current_line.length - parser.offset)
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
                parser.add_child(hr)
                parser.move_offset(parser.current_line.length - parser.offset)
                next true
              end
              false
            }
        },
        ListItem => {
            :continue => proc { |parser, node|
              if parser.on_blank_line && !node.first_child.nil?
                parser.move_to_next_nonspace
              elsif parser.indent >= (node.marker_offset + node.padding)
                parser.move_offset_by_columns(node.marker_offset + node.padding)
              else
                next false
              end
              true
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

              parser.move_to_next_nonspace

              prepadding = match[0].length
              unless spaces_after_marker.between?(1, 4) && prepadding != ln.length
                prepadding -= (spaces_after_marker + 1)
              end
              list_node.marker_offset = parser.indent
              old_col = parser.column
              parser.move_offset(prepadding)
              list_node.padding = parser.column - old_col

              if parser.current_block.instance_of?(Paragraph)
                parser.finalize_current_block
                if parser.current_block.instance_of?(ListItem) && parser.current_block.matches?(list_node)
                  parser.finalize_current_block
                end
              end

              if !parser.current_block.instance_of?(List) || !parser.current_block.matches?(list_node)
                parser.add_child(List.new(list_node.is_ordered))
                parser.current_block.copy_properties(list_node)
              end
              parser.add_child(list_node)
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
                  parser.move_offset(1)
                  i -= 1
                end
                next true
              end

              #indented code
              if parser.indent >= 4
                parser.move_offset_by_columns(4)
              elsif parser.on_blank_line
                parser.move_to_next_nonspace
              else
                next false
              end
              true
            },
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.indent >= 4 && parser.current_block.class != Paragraph && !parser.on_blank_line
                  parser.move_offset_by_columns(4)
                  cb = Code.new
                  parser.add_child(cb)
                  next true
              end

              if match = REGEX_CODEFENCE.match(parser.current_line[parser.next_nonspace..-1])
                cb = Code.new(true, match[0][0], match[0].length, parser.indent)
                parser.add_child(cb)
                parser.move_to_next_nonspace
                parser.move_offset(cb.fence_length)

                if parser.offset < parser.current_line.length && info = parser.current_line[parser.offset..-1].strip
                  cb.info_string = info if info.length > 0
                  parser.move_offset(parser.current_line.length - parser.offset)
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
                parser.add_child(b)
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

    def initialize(debug = false)
      @debug = debug
      @doc = Document.new
      @current_block = @doc
      @current_line = nil
      @line_number = 0
      @offset = 0
      @column = 0
      @indent = 0
      @next_nonspace = 0
      @next_nonspace_column = 0
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
        finalize_current_block
      end
      parse_inlines(@doc)
      puts @doc.to_s if @debug
      @doc
    end

    def parse_inlines(block)
      iparser = InlineParser.new
      walker = NodeWalker.new(block)
      current = walker.next

      until current.nil?
        if !walker.entering && (current.instance_of?(Paragraph) || current.instance_of?(Header))
          iparser.parse_block(current)
        end
        current = walker.next
      end
    end

    def incorporate_line(line)
      @current_line = line
      @offset = 0

      find_next_nonspace

      @last_matched_block = nil
      should_continue = true

      b = @doc
      while @last_matched_block.nil? && !b.nil? && b.open
        should_continue = @@helpers[b.class][:continue].call(self, b)
        unless should_continue
          @last_matched_block = b.parent
        end
        b = b.last_child
      end

      # code block, easy peasy
      if should_continue && @current_block.accepts_lines? && @current_block.class != Paragraph
        add_line_to_block
        return
      end

      if @on_blank_line
        return if @last_line_blank && close_all_lists(@current_block)
      end

      unless @last_matched_block.nil? || @last_matched_block.last_child.nil?
        block_to_close = @last_matched_block.last_child
        if block_to_close.class == Paragraph && block_to_close.parent.class == ListItem
          block_to_close.parent.last_line_blank = true
          block_to_close.last_line_blank = true
        end

        if block_to_close == @current_block
          finalize_current_block
          return if (block_to_close.class == Code && block_to_close.is_fenced) || block_to_close.class == Paragraph
        end
      end

      # try all node starts, stopping when we've hit a leaf to add our line
      can_add_line = false
      line_finished = false
      until can_add_line
        find_next_nonspace
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
          move_to_next_nonspace
          return if @on_blank_line
          unless @current_block.class == Paragraph
            p = Paragraph.new
            add_child(p)
          end
          can_add_line = true
        end
      end

      add_line_to_block
    end

    def finalize_block(node)
      node.open = false
      @@helpers[node.class][:finalize].call(self, node)
    end

    def finalize_current_block
      @current_block.open = false
      @@helpers[@current_block.class][:finalize].call(self, @current_block)
      @current_block = @current_block.parent
    end

    def ends_with_blank_line(node)
      n = node
      while n && (n.class <= List || n.class == Paragraph)
        return true if n.last_line_blank

        if n.class <= List
          n = n.last_child
        else
          break
        end
      end
      false
    end

    def add_line_to_block
      if @offset >= @current_line.length
        @current_block.strings.push("")
      else
        @current_block.strings.push(@current_line[@offset..-1])
      end
    end

    def expand_tabs(line)
      line.gsub(/([^\t]*)\t/) {$1 + ' ' * (4 - ($1.length % 4))}
    end

    def close_all_lists(node)
      b = node
      tree_changed = false
      while b.class <= List
        finalize_block(b)
        tree_changed = true
        b = b.parent
      end
      @current_block = b
      tree_changed
    end

    def find_next_nonspace
      line = @current_line
      i = @offset
      cols = @column

      until i == line.length
        if line[i] == ' '
          i += 1
          cols += 1
        elsif line[i] == "\t"
          i += 1
          cols += (4 - (cols % 4))
        else
          break
        end
      end

      @on_blank_line = line.length == 0
      @next_nonspace = i
      @next_nonspace_column = cols
      @indent = @next_nonspace_column - @column
    end

    def move_to_next_nonspace
      @column = @next_nonspace_column
      @offset = @next_nonspace
    end

    def move_offset(count)
      i = 0
      cols = 0
      l = @current_line

      while i < count
        cols += if l[@offset + i] == "\t"
                  4 - ((@column + cols) % 4)
                else
                  1
                end
        i += 1
      end
      @offset += i
      @column += cols
    end

    def move_offset_by_columns(count)
      i = 0
      cols = 0
      l = @current_line

      while cols < count
        cols += if l[@offset + i] == "\t"
                  4 - ((@column + cols) % 4)
                else
                  1
                end
        i += 1
      end
      @offset += i
      @column += cols
    end

    def char_code_at(line, position)
      return -1 unless position < line.length
      line[position].ord
    end

    def add_child(child)
      container = @current_block

      if @last_matched_block && container != @last_matched_block
        until container == @last_matched_block
          finalize_block(container)
          container = container.parent
        end
      end

      @last_matched_block = nil

      until container.can_contain?(child)  # go up until we find a container
        finalize_block(container)
        container = container.parent
      end
      container.add_child(child)
      @current_block = child
      @current_block
    end
  end
end