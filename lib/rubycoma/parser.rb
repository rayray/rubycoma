module RubyCoMa
  require_relative 'nodes'
  require_relative 'inline_parser'
  require_relative 'common'

  class Parser
    include Nodes
    include Common

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
    attr_accessor :ref_map
    attr_reader   :iparser

    CHARCODE_LESSTHAN           = 60
    CHARCODE_GREATERTHAN        = 62
    CHARCODE_SPACE              = 32
    CHARCODE_TAB                = 9
    CHARCODE_NEWLINE            = 10
    CHARCODE_LEFTSQUAREBRACKET  = 91

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
              if parser.indent < 4 && parser.char_code_at(parser.current_line, parser.next_nonspace) == CHARCODE_GREATERTHAN
                parser.move_to_next_nonspace
                parser.move_offset(1)
                cc = parser.char_code_at(parser.current_line, parser.offset)
                parser.move_offset(1) if cc == CHARCODE_SPACE || cc == CHARCODE_TAB
                parser.close_unmatched_blocks
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
                parser.close_unmatched_blocks
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
                parser.close_unmatched_blocks
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
                parser.close_unmatched_blocks
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
              parser.close_unmatched_blocks
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
                next false if match && match[0].length >= container.fence_length && ln[parser.next_nonspace..-1].strip.length == match[0].length

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
            :finalize => proc { |parser, block|
              unless block.is_fenced
                str = block.strings.join("\n")
                str.gsub!(/(\n *)+\Z/, "\n")
                block.strings = str.split("\n")
              end
              block.strings << ""
            },
            :start    => proc { |parser|
              if parser.indent >= 4 && parser.current_block.class != Paragraph && !parser.on_blank_line
                  parser.move_offset_by_columns(4)
                  parser.close_unmatched_blocks
                  cb = Code.new
                  parser.add_child(cb)
                  next true
              end

              if match = REGEX_CODEFENCE.match(parser.current_line[parser.next_nonspace..-1])
                cb = Code.new(true, match[0][0], match[0].length, parser.indent)
                parser.close_unmatched_blocks
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
            :continue => proc { |parser, container|
              !(parser.on_blank_line && ((6..7) === container.block_type))
            },
            :finalize => proc {},
            :start    => proc { |parser|
              if parser.indent <= 3 && parser.char_code_at(parser.current_line, parser.next_nonspace) == CHARCODE_LESSTHAN
                str = parser.current_line[parser.next_nonspace..-1]
                match_found = false

                REGEX_HTMLOPENS.each_with_index { |re, idx|
                  block_type = idx + 1
                  match = re.match(str)

                  if match && (block_type < 7 || parser.current_block.class != Paragraph)
                    parser.close_unmatched_blocks
                    b = HTML.new
                    b.block_type = block_type
                    parser.add_child(b)
                    match_found = true
                    break
                  end
                }
                next match_found
              end
              false
            }
        },
        Paragraph => {
            :continue => proc { |parser|
              !parser.on_blank_line
            },
            :finalize => proc { |parser, block|
              pos = 0
              has_ref_defs = false
              string_content = block.strings.join("\n")

              while parser.char_code_at(string_content, 0) == CHARCODE_LEFTSQUAREBRACKET
                pos = parser.iparser.parse_link_reference(string_content, parser.ref_map)
                break if pos == 0
                string_content = string_content[pos..-1]
                has_ref_defs = true
              end

              if has_ref_defs && string_content.strip.length < 1
                block.remove
                next
              end

              block.strings = string_content.split("\n")
            },
            :start    => proc {false}
        }
    }

    def initialize(debug = false)
      @debug = debug
      @doc = Document.new
      @current_block = @doc
      @previous_block = nil
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
      @ref_map = Hash.new
      @iparser = InlineParser.new
      @all_closed = true
      @last_matched_block = @doc
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
        @line_number += 1
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
      @iparser.ref_map = @ref_map
      walker = NodeWalker.new(block)
      current = walker.next

      until current.nil?
        if !walker.entering && (current.instance_of?(Paragraph) || current.instance_of?(Header))
          @iparser.parse_block(current)
        end
        current = walker.next
      end
    end

    def incorporate_line(line)
      @current_line = line
      @offset = 0

      @previous_block = @current_block
      should_continue = true

      b = @doc

      while !b.nil? && b.open
        find_next_nonspace
        should_continue = @@helpers[b.class][:continue].call(self, b)

        if should_continue
          break if b.last_child.nil? || !b.last_child.open
          b = b.last_child
        else
          # fenced code we can just stop here
          if b.class == Code && b.is_fenced
            @last_line_length = line.length
            return
          end
          b = b.parent
          break
        end
      end

      @all_closed = (b == @previous_block)
      @last_matched_block = b

      if @on_blank_line && b.last_line_blank
        close_all_lists(b)
        b = @current_block
      end

      matched_leaf = b.class == Code

      until matched_leaf
        find_next_nonspace

        if @indent < 4 && REGEX_MAYBESPECIAL.match(@current_line[@next_nonspace..-1]).nil?
          move_to_next_nonspace
          break
        end

        counter = 0
        @@helpers.each_value { |type|
          if type[:start].call(self)
            if @current_block.class < Leaf
              matched_leaf = true
            end
            b = @current_block
            break
          end
          counter += 1
        }

        if counter == @@helpers.count
          move_to_next_nonspace
          break
        end
      end

      if !@all_closed && !@on_blank_line && @current_block.class == Paragraph
        add_line_to_block
      else
        close_unmatched_blocks
        if @on_blank_line && !b.last_child.nil?
          b.last_child.last_line_blank = true
        end

        type = b.class

        last_line_blank = @on_blank_line &&
            !(type == BlockQuote || (type == Code && b.is_fenced) || (type == ListItem && b.first_child.nil?))

        container = b
        until container.nil?
          container.last_line_blank = last_line_blank
          container = container.parent
        end

        if b.accepts_lines?
          add_line_to_block

          if @current_block.class == HTML && (1..5) === @current_block.block_type
            match = REGEX_HTMLCLOSES[@current_block.block_type - 1].match(@current_line[@offset..-1])
            if match
              finalize_current_block
            end
          end
        elsif @offset < line.length && !@on_blank_line
          p = Paragraph.new
          add_child(p)
          move_to_next_nonspace
          add_line_to_block
        end
      end
      @last_line_length = line.length
    end


    def finalize_block(block)
      p = block.parent
      block.open = false
      block.end_line = @line_number
      block.end_column = @last_line_length
      @@helpers[block.class][:finalize].call(self, block)
      @current_block = p
    end

    def finalize_current_block
      finalize_block @current_block
    end

    def ends_with_blank_line(node)
      while node
        return true if node.last_line_blank

        c = node.class

        if c == ListItem || c == List
          node = node.last_child
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

    def close_all_lists(block)
      b = block
      last_list = nil
      until b.nil?
        if b.class <= List
          last_list = b
        end
        b = b.parent
      end
      unless last_list.nil?
        until block == last_list
          finalize_block(block)
          block = block.parent
        end
        finalize_block(last_list)
        @current_block = last_list.parent
      end
    end

    def close_unmatched_blocks
      unless @all_closed
        until @previous_block == @last_matched_block
          parent = @previous_block.parent
          finalize_block(@previous_block)
          @previous_block = parent
        end
        @all_closed = true
      end
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

      @on_blank_line = i >= line.length
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
      until @current_block.can_contain?(child)
        finalize_current_block
      end

      @current_block.add_child(child)
      @current_block = child
      @current_block
    end
  end
end