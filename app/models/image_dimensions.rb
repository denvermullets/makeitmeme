# Reads [width, height] from the header bytes of a PNG, JPEG or WebP, without decoding the image.
# Returns nil when the bytes aren't one of those or the header is truncated.
module ImageDimensions
  module_function

  def of(bytes)
    b = bytes.b
    if b.start_with?("\x89PNG\r\n\x1a\n".b) then png(b)
    elsif b.start_with?("\xFF\xD8".b) then jpeg(b)
    elsif b.start_with?('RIFF'.b) && b[8, 4] == 'WEBP'.b then webp(b)
    end
  end

  def png(bytes)
    bytes.unpack('@16NN') if bytes.bytesize >= 24
  end

  def jpeg(bytes)
    pos = 2
    while pos + 9 <= bytes.bytesize
      return nil unless bytes.getbyte(pos) == 0xFF

      marker = bytes.getbyte(pos + 1)
      if marker == 0xFF then pos += 1
      elsif [0x01, *0xD0..0xD8].include?(marker) then pos += 2
      elsif (0xC0..0xCF).include?(marker) && [0xC4, 0xC8, 0xCC].exclude?(marker)
        h, w = bytes.unpack("@#{pos + 5}nn")
        return [w, h]
      else pos += 2 + bytes.unpack1("@#{pos + 2}n")
      end
    end
    nil
  end

  def webp(bytes)
    case bytes[12, 4]
    when 'VP8 '.b then bytes.unpack('@26vv').map { |v| v & 0x3FFF } if bytes.bytesize >= 30
    when 'VP8L'.b
      return nil if bytes.bytesize < 25

      bits = bytes.unpack1('@21V')
      [(bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1]
    when 'VP8X'.b
      return nil if bytes.bytesize < 30

      w = bytes.unpack('@24C3').each_with_index.sum { |v, i| v << (8 * i) } + 1
      h = bytes.unpack('@27C3').each_with_index.sum { |v, i| v << (8 * i) } + 1
      [w, h]
    end
  end

  private_class_method :png, :jpeg, :webp
end
