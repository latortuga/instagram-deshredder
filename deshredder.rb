require 'RMagick'

# return a float between 0 and 1 indicating how well the right side of shred1
# matches the left side of shred2. The closer to 1.0, the better the match.
def closeness(shred1, shred2)
  return -1 if shred1 == shred2

  col1 = shred1[][Width-1]
  col2 = shred2[][0]

  matches = 0

  # Use Pixel#fcmp with a fuzz of 5000. For the sample photo
  # this seemed to return results that have decent resolution
  # though I'm not certain that this will apply to all photos.
  col1.each_with_index do |px, idx|
    matches += 1 if px.fcmp(col2[idx], 5000.0)
  end

  matches / Rows.to_f
end

# take an array of shreds as Image::View objects and return an array of hashes
# with the following attributes:
#   :match - how close, between 0 and 1, of a match
#   :shred_index - the index of the shred
#
# the order of the array is the order that the shreds should be sewn together
def arrange_shreds(shreds)
  match_data = []

  puts "Finding right-most edge..."

  # Iteratively find the closest match to the right side of the first shred.
  0.upto(shreds.length-1) do
    match_data << {:match => 0.0, :shred_index => nil}

    shreds.each_with_index do |shred,idx|
      # compare previous shred with current shred
      check_shred = if match_data.size == 1
        shreds.first
      else
        shreds[match_data[-2][:shred_index]]
      end

      check = closeness(check_shred, shred)
      next if check == -1 # skip comparing equivalent shreds

      # let the best match bubble to the top
      if check > match_data.last[:match]
        match_data.last[:match] = check
        match_data.last[:shred_index] = idx
      end
    end

    break if match_data.last[:shred_index].nil?
  end

  # Find the worst matching shred.
  worst = match_data.min{ |a,b| a[:match] <=> b[:match] }
  idx = match_data.index(worst)

  puts "Rearranging shreds assuming shred #{idx+1} is the right-most edge..."

  # Insert the right edge and any shreds to the left of it to the final data
  final_data = match_data[0..idx-1]

  # This is the same as above but is conducted in reverse and is seeded by
  # the worst match as the right-most border.
  0.upto(shreds.length - final_data.length - 1) do
    final_data.unshift({:match => 0.0, :shred_index => nil})

    shreds.each_with_index do |shred,idx|
      # compare previous shred with current shred
      check_shred = shreds[final_data[1][:shred_index]]

      # compare opposite shreds as above because we're inserting before
      # check_shred, instead of after.
      check = closeness(shred, check_shred)
      next if check == -1

      if check > final_data.first[:match]
        final_data.first[:match] = check
        final_data.first[:shred_index] = idx
      end
    end

    break if final_data.first[:shred_index].nil?
  end

  final_data
end

# Read image
source = Magick::Image.read(ARGV[0]).first

Width = 32
Columns = source.columns
Rows = source.rows

# Calculate shred count
shred_count = Columns / Width

# Break image up into shreds
puts "Cutting image into shreds..."
shreds = 0.upto(shred_count-1).map do |shred_number|
  x = shred_number * Width
  y = 0
  width = Width
  height = Rows

  source.view(x, y, width, height)
end

# Arrange shreds by matching edges as best as possible
final_shreds = arrange_shreds(shreds)

# Write new image with sorted shreds
puts "Writing final image..."
unshredded = Magick::Image.new(Columns, Rows)

final_shreds.map {|obj| shreds[obj[:shred_index]] }.each_with_index do |shred,idx|
  x = idx * Width
  y = 0
  columns = Width
  rows = Rows
  pixels = shred[][]

  unshredded.store_pixels(x, y, columns, rows, pixels)
end

unshredded.write("out.png")
puts "Done."
