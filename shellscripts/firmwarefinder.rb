#!/usr/bin/ruby

@startdir = ARGV[0] 
@targetdir = ARGV[1]

puts "Starting in #{@startdir}"
puts "Install to #{@targetdir}"  
system("mkdir -p #{@targetdir}")

@kos = Hash.new 

def get_kos(subdir)
	puts "Traversing #{@targetdir}/lib/modules/#{@startdir}/#{subdir}"
	Dir.entries("#{@targetdir}/lib/modules/#{@startdir}/#{subdir}").each { |d|   
		if d =~ /\.ko$/ 
			@kos["#{@startdir}/#{subdir}/#{d}"] = Array.new
			IO.popen("modinfo #{@targetdir}/lib/modules/#{@startdir}/#{subdir}/#{d}") { |line|
				while line.gets
                   		     	begin
						if $_ =~ /^firmware/
							ltoks = $_.strip.split
							@kos["#{@startdir}/#{subdir}/#{d}"].push(ltoks[1])
						end
					rescue
						puts "ERROR PARSING: #{$_}"
					end
                		end	
			}
		end
		unless d == "." || d == ".." 
			if File.directory?("#{@targetdir}/lib/modules/#{@startdir}/#{subdir}/#{d}")
				get_kos("#{subdir}/#{d}")
			end
		end
	}
end

get_kos('') 

@kos.each { |k,v|
	v.each { |f| 
		if File.exists?("#{@targetdir}/lib/firmware/#{f}")
			# puts "Found:   #{f}"
		elsif File.exists?("linux-firmware/#{f}")
			# puts "Install: #{f}"
			system("tar -C linux-firmware -cf - #{f} | tar -C #{@targetdir}/lib/firmware -xf - ") 
		else	
			puts "Missing: #{f} needed by #{k}"
		end
	}
}

