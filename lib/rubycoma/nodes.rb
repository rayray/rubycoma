module Nodes

  class DLLNode
    attr_accessor :next
    attr_accessor :prev

    def initialize
      @prev = nil
      @next = nil
    end

    def remove
      unless @prev.nil?
        @prev.next = @next
      end

      unless @next.nil?
        @next.prev = @prev
      end

      @prev, @next = nil, nil
    end

    def insert(node)
      unless @next.nil?
        @next.prev = node
        node.next = @next
      end

      @next = node
      node.prev = self
    end
  end

  class Inline < DLLNode
    :text
    :normal
    :emphasized
    :strong
    :strikethrough
    :code_span
    :link
    :image

    attr_accessor :style
    attr_accessor :content
    attr_accessor :children
    attr_accessor :parent

    def initialize(style, content = nil)
      super
      @style = style
      @content = content
      @attributes = Hash.new
      @children = Array.new
      @parent = nil
    end

    def add_child(child)
      child.parent = self
      @children.push(child)
    end

    def remove_child(block_to_delete)
      @children.delete(block_to_delete)
    end

    def to_s(indent = 0)
      str = ' ' * indent << "{\n"
      str << ' ' * (indent+2) << "style: #{@style}\n"
      str << ' ' * (indent+2) << "content: #{@content}\n"
      str << ' ' * indent << "}\n"
      str
    end
  end

  class Block
    attr_accessor :parent
    attr_accessor :open

    def initialize
      @parent = nil
      @open = true
    end

    def type
      self.class.name
    end

    def to_s(indent = 0)
      var_indent = indent + 2
      arr_indent = indent + 4
      str =  ' ' * indent << "{\n"
      str << ' ' * var_indent << "class: " << self.class.name << "\n"

      self.instance_variables.each { |var|
        next if var == :@parent
        value = instance_variable_get(var)

        if value.class == Array && value.count > 0
          str << ' ' * var_indent << "#{var}: [\n"
          value.each { |obj|

            if obj.class <= Block
              str << obj.to_s(arr_indent)
            elsif obj.class == String
              str << ' ' * arr_indent << "\"#{obj.to_s}\"\n"
            end
          }
          str << ' ' * var_indent << "]\n"
        else
          str << ' ' * var_indent << "#{var}: #{value}\n"
        end
      }

      str << ' ' * indent << "}\n"
      str
    end

    def accepts_lines?
      false
    end

    def can_contain?(block)
      false
    end

  end

  class Leaf < Block
    attr_accessor :strings
    attr_accessor :inlines

    def initialize
      super
      @strings = Array.new
      @inlines, @inlines_head = nil, nil
    end

    def accepts_lines?
      true
    end

    def can_contain?(block)
      false
    end

    def add_inline(inline)
      unless @inlines.nil?
        @inlines.insert(inline)
      end
      @inlines = inline
    end

    def remove_inline(inline)
      if inline == @inlines
        @inlines == @inlines.prev
      end

      inline.remove
    end
  end

  class Paragraph < Leaf; end
  class HTML < Leaf; end
  class Code < Leaf
    attr_accessor :is_fenced
    attr_accessor :fence_character
    attr_accessor :fence_length
    attr_accessor :fence_offset
    attr_accessor :info_string

    def initialize(fenced = false, char = nil, length = nil, offset = nil)
      super()
      @is_fenced = fenced
      if char && length && offset
        @fence_character, @fence_length, @fence_offset = char, length, offset
      end
    end
  end

  class HorizontalRule < Leaf; def accepts_lines?; false; end; end
  class Header < Leaf
    attr_accessor :level
    def initialize(l)
      super
      @level = l
    end
    def accepts_lines?; false; end
  end


  class Container < Block
    attr_reader :children

    def initialize
      super
      @children = Array.new
    end

    def add_child(new_block)
      new_block.parent = self
      @children.push(new_block)
    end

    def remove_child(block_to_delete)
      @children.delete(block_to_delete)
    end

    def can_contain?(block)
      block.class != ListItem
    end
  end

  class Document < Container; end
  class BlockQuote < Container; end

  class List < Container
    attr_accessor :is_ordered
    attr_accessor :is_tight
    attr_accessor :marker_character
    attr_accessor :start
    attr_accessor :delimiter
    attr_accessor :marker_offset
    attr_accessor :padding

    def can_contain?(block); block.class == ListItem; end;
    def initialize(ordered)
      super()
      @is_tight = true
      @is_ordered = ordered
    end

    def matches?(l)
      @is_ordered == l.is_ordered && @delimiter == l.delimiter && @marker_character == l.marker_character
    end

    def copy_properties(l)
      @is_ordered = l.is_ordered
      @is_tight = l.is_tight
      @marker_character = l.marker_character
      @start = l.start
      @delimiter = l.delimiter
      @marker_offset = l.marker_offset
      @padding = l.padding
    end
  end

  #inheritance abuse!
  class ListItem < List
    def can_contain?(block)
      block.class != ListItem
    end
  end
end
