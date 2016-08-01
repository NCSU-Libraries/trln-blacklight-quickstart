#!/usr/bin/env ruby
 
require 'rubygems'
require 'rubygems/package'
require 'zlib'
require 'nokogiri'
require 'net/http'
require 'net/https'
require 'open-uri'
require 'uri'
require 'digest/sha1'
require 'cocaine'


class SolrServer
	attr_accessor :base_uri, :core_name, :port, :install_dir, :version

	@config
	
	def initialize(config)
		@config = config
		@core_name = config[:core_name] || 'blacklight-core'
		@port = config[:port] || 8983
		@version = config[:version]
		@install_dir =  File.absolute_path(config[:install_dir], Rails.root)
		@base_uri = URI("http://localhost:#{@port}/solr/#{@core_name}")
		@solr_cmd = File.join(@install_dir, "solr-#{@version}/bin/solr")
	end

	
	def is_running?
		line = Cocaine::CommandLine.new(
			"lsof", ":ports", expected_outcodes: [0,1]
		)
	  	begin
        		output = line.run(ports: ["-iTCP", "-i:#{@port}"])
                	if output != ''
				# lsof says something's holding the port open
				return true
			end
			return false
       		rescue Cocaine::ExitStatusError => e
        		puts e
	                exit 1
        	end
		# looks like we got return code 1 from lsof, meaning port is open
		return false
	end
	
	def core_exists?
		uri = URI(@base_uri.to_s)
		uri.path += "/select"
		uri.query = "wt=json"
		res = Net::HTTP.get_response(uri)
		return res.is_a?(Net::HTTPSuccess)
	end

	def create_core
		uri = URI(@base_uri.to_s)
		uri.path = "/solr/admin/cores"
		uri.query = URI.encode_www_form(
			:action => "CREATE",
			:name => @core_name,
			:instanceDir => File.absolute_path("solr/conf", Rails.root),
	 		:dataDir => '../data'
		)
		res = Net::HTTP.get_response(uri)
		if not res.is_a?(Net::HTTPSuccess)
			puts "Core creation failed, code was #{res.code} : #{res.message}"
			puts "Response body:"
			puts res.body
			return false
		end
		true
	end

	def commit
	 	uri = URI(@base_uri.to_s)
                uri.path += "/update"
                uri.query = "commit=true"
                res = Net::HTTP.get_response(uri)
                return res.is_a?(Net::HTTPSuccess)
	end
	

	def delete_core

		uri = URI(@base_uri.to_s)
		uri.path = "/solr/admin/cores"
		uri.query = URI.encode_www_form(
			:action => "UNLOAD",
			:core => @core_name,
		)
		res = Net::HTTP.get_response(uri)
		if not res.is_a?(Net::HTTPSuccess)
			puts "Core delete (unload) failed, code was #{res.code} : #{res.message}"
			puts "Response body:"
			puts res.body
			return false
		end
		true
	end
		

	def start
		return true if is_running?
		begin
                	start_line = Cocaine::CommandLine.new(
                		"#{@solr_cmd}",
	                        ":args")
        	        start_line.run( args: [ "start", 
						"-p", 
						"#{@port}" ] 
			)
                	puts "Started solr on port #{@port}"
       		end
		true
	end

	def stop
		begin 
			stop_line = Cocaine::CommandLine.new(
					"#{@solr_cmd}", ":args")
				 	stop_line.run(args: ["stop", "-p", "#{@port}" ])
		rescue Cocaine::ExitStatusError => e
			puts e
			exit 1
		end
	end

	
end
	

class Extractor 
	attr_accessor :source, :dest

	@@TAR_LONGLINK = '././@LongLink'

	def initialize(source, dest)
		@source = source
		@dest = dest
	end

	def extract()
		dest = nil
		puts "Extracting #{@source}"
		Gem::Package::TarReader.new(Zlib::GzipReader.open(@source)) do
		   	|tar|
			tar.each do |entry|
				if entry.full_name == @@TAR_LONGLINK
					dest = File.join @dest,entry.read.strip 
					next
				end
				dest ||= File.join @dest, entry.full_name

				if entry.directory?
					FileUtils.rm_rf dest unless File.directory? dest
					FileUtils.mkdir_p dest, :mode =>entry.header.mode, :verbose => false
				elsif entry.file?
					FileUtils.rm_rf dest unless File.file? dest
					dirname = File.dirname dest
					FileUtils.mkdir_p dirname unless File.directory? dirname
					File.open dest, "wb" do |f|
						f.print entry.read
					end
					FileUtils.chmod entry.header.mode, dest, :verbose => false
				elsif entry.header.typeflag == '2'
					File.symlink entry.header.linkname, dest
				end
				dest = nil
			end # tar.entry
		end # tar.read
	end # method
end
				

class Fetcher

	MIRROR_BASE = "https://www.apache.org/dyn/closer.lua/lucene/solr/%{version}"

	SHA_BASE = "https://archive.apache.org/dist/lucene/solr/%{version}/solr-%{version}.tgz.sha1"

	@download_dir

	@version = '5.5.2'

	@sha_uri

	@mirror_uri

	@download_uri

	@target
	
	@install_dir
	
	def initialize(output_dir,version="5.5.2",download_dir=Dir.tmpdir)
		@output_dir = output_dir
		filename = "solr-#{version}.tgz"
		@version = version
		@sha_uri = URI(SHA_BASE % {version:version})
		@mirror_uri = URI(MIRROR_BASE % {version:version})
		@target = File.join(download_dir,filename)
		@install_dir = File.join(output_dir, "solr-#{version}")
	end

	def get_download_uri()
		if @download_uri
			return @download_uri
		end
		page = Nokogiri::HTML(Net::HTTP.get(@mirror_uri))

		dl_index = page.css(".container a").select { |link|
			link['href'] =~ /#{@version}$/
		}[0]['href']

		dl_index += '/' unless dl_index[-1] == '/'

		dl_page = Nokogiri::HTML(Net::HTTP.get(URI(dl_index)))

		dl_path = dl_page.css("a").select {
			|link|
			link['href'] =~ /solr-#{@version}.tgz/
		}[0]['href']

		@download_uri = URI.join(dl_index,dl_path)
		return @download_uri
	end

	def fetch()
		if not File.size? @target
			File.open(@target,'w') do |f|
				IO.copy_stream( open(get_download_uri),f )
			end
		end
		if not verify
			puts "Checksums don't match.  Not unpacking"
			exit 1
		end
	end

	def installed?()
		File.exists? File.join(@output_dir, "solr-#{@version}/bin/solr")
	end

	def unpack()
		e = Extractor.new(@target,@output_dir)
		if not File.directory? @output_dir
			FileUtils.mkdir_p @output_dir
		end
		e.extract()
	end

	def install() 
		if not installed?
			fetch
			verify
			unpack
		end
	end

	def verify()
		sha_file = "#{@target}.sha1"
		if not File.exists? sha_file or not File.size? sha_file
			sha_value = Net::HTTP.get(@sha_uri).split(' ').first
			File.open(sha_file,"w") do |f|
				f.write sha_value
			end
		else
			File.open(sha_file) do |f|
				sha_value = f.read
			end
		end
		if not File.exists? @target
			puts "Can't verify file.  Call fetch first"
			exit 1
		end
		actual_sha = Digest::SHA1.file(@target).hexdigest()
		raise "Checksum of downloaded file #{@target} does not match" unless actual_sha == sha_value
		true
	end # verify()
end # class
