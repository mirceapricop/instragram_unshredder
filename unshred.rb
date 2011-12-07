require 'rubygems'
require 'RMagick'

include Magick

def column_at(x,image)
  result = Array.new
  (0..image.rows).each do |y|
    result << image.pixel_color(x, y)
  end
  result
end

def last_column(image)
  column_at(image.columns, image)
end

def first_column(image)
  column_at(0, image)
end

def column_distance(a, b)
  pixel_distances = Array.new
  a.each_with_index do |a_pix, i|
    b_pix = b[i]
    channel_diffs = [:red, :green, :blue].map { |channel|
      a_pix.send(channel) - b_pix.send(channel)
    }
    red_mean = (a_pix.red + b_pix.red) / 2.0
    # Custom color distance metric taken from
    # http://www.compuphase.com/cmetric.htm
    # Honestly I couldn't understand that log space magic
    pixel_distances << Math.sqrt(
      (2 + red_mean.to_f / QuantumRange) * channel_diffs[0]**2 +
      4 * channel_diffs[1]**2 +
      (2 + (QuantumRange-1 - red_mean.to_f)/QuantumRange) * channel_diffs[2]**2
    )
  end
  pixel_distances.reduce(:+)
end

puts "Reading original and bumping contrast.."
original = Image.read("input.png").first
bumped = original.sigmoidal_contrast_channel(3, 50, true)

puts "Figuring out shred width.."
# best width has the biggest average difference between shred edges
best_width = -1
best_average = -1
(2..original.columns/2).each do |width|
  next if original.columns % width != 0
  dif_sum = 0
  (width..original.columns-width).step(width) do |edge|
    dif_sum += column_distance(
      column_at(edge-1, original),
      column_at(edge, original))
  end
  average = dif_sum.to_f / (original.columns / width)
  if average > best_average
    best_width = width
    best_average = average
  end
end

puts "Figured best shred width is #{best_width}.."

puts "Taking shreds apart (this takes a while, weird).."
original_shreds = ImageList.new
bumped_shreds = ImageList.new

(0..original.columns-best_width).step(best_width) do |left|
  original_shreds << original.crop(left, 0, best_width, original.rows, true)
  bumped_shreds << bumped.crop(left, 0, best_width, original.rows, true)
end

puts "Figuring out how they belong.."
num_shreds = original_shreds.length
shred_pool = (0..num_shreds-1).to_a
result = Array.new

num_shreds.times do 
  if result.empty?
    result << shred_pool.shift
    next
  end

  # find the best fit to the left or right of current solution
  best = {}
  shred_pool.each do |shred_index|

    left = {
      :score => column_distance(
          last_column(bumped_shreds[shred_index]),
          first_column(bumped_shreds[result.first])
        ),
      :position => :left
    }

    right = {
      :score => column_distance(
          first_column(bumped_shreds[shred_index]),
          last_column(bumped_shreds[result.last])
          ),
      :position => :right
    }

    candidate = left
    candidate = right if right[:score] < left[:score]

    if best[:score].nil? || (candidate[:score] < best[:score])
      best = candidate
      best[:shred] = shred_index
    end
  end

  if best[:position] == :right
    result.push best[:shred]
  else
    result.unshift best[:shred]
  end
  shred_pool.delete best[:shred]
end

output = ImageList.new
result.each do |shred_index|
  output << original_shreds[shred_index]
end

puts "Done, putting them back together and writing.."
output.append(false).write("output.png")
