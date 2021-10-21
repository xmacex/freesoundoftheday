#!/usr/bin/lua

io       = require 'io'
lfs      = require 'lfs'
lunajson = require 'lunajson'

local API_ENDPOINT = "https://freesound.org/apiv2/"
local API_TOKEN    = "7GpLkaFEHHF4m2zPzhmKyfZEgCP0G1l12VqVGKg7"
local DIRECTORY    = "/home/we/dust/audio/freesoundoftheday/"

local debug = true

--------------- network connections -----------------

function get_frontpage(path)
   local content = nil
   if (path ~= nil) then
      if debug then print("🗄 Getting frontpage from file.") end
      local fd = io.open(path, 'r')
      content = fd:read '*all'
      fd:close()
      if debug then print("🗜 Read "..#content.."B frontpage from file.") end
   else
      if debug then print("📡 Getting frontpage from network.") end
      local response = assert(io.popen("curl -s https://freesound.org"))
      content = response:read '*all'
      response:close()
      if debug then print("🗜 Read "..#content.."B frontpage from network.") end
   end
   return content
end

function get_featured_sound_id(frontpage)
   if debug then print("🔐 Looking for sound id.") end
   -- assumes it's the first player on the page. Sad.
   local pattern = 'class="sample_player_small" id="(%d+)"'
   local featured_sound_id = string.match(frontpage, pattern)
   if debug then print("🔑 Found sound id "..featured_sound_id) end
   return featured_sound_id
end

function get_sound_metadata(sound_id)
   if debug then print("📡 Getting metadata for sound id "..sound_id) end
   local metadata = query_api("sounds", sound_id)
   local parsed   = parse_metadata(metadata)
   return parsed
end

function get_sound_preview(metadata)
   if debug then print("💿 Downloading preview for "..metadata['name']) end
   local filename = extract_preview_filename(metadata)
   local complete_path = "/tmp/"..filename
   download_file(metadata['previews']['preview-hq-mp3'], complete_path)
   return complete_path
end

--------------- lower level network connections -------

function download_file(url, filename)
   if debug then print("📡 Downloading file from "..url) end
   -- io.popen("curl -s "..url.. " -o "..DIRECTORY..filename)
   io.popen("curl -s "..url.." -o "..filename)
end

function query_api(resource, param)
   -- Just takes a single parameter rather than a table.
   local query_url = API_ENDPOINT..resource.."/"..param.."/"
   local auth_url = query_url.."?token="..API_TOKEN
   if debug then print("🛂 "..auth_url) end
   local response = assert(io.popen("curl -s "..auth_url..";sync"))
   local content = response:read '*all'
   response:close()
   -- if debug then print("📇 Read metadata "..content) end
   return content
end

----------------- manage files ---------------

function some_sounds_already_on_disk(directory)
   local files = {}
   for filename in lfs.dir(directory) do
      if filename ~= "." and filename ~= ".." then
         table.insert(files, filename)
      end
   end
   return (#files > 0)
end

function sound_already_on_disk(directory, metadata)
   local filename_would_be = create_richer_preview_filename(metadata)
   if debug then print("🗃 Checking for file "..filename_would_be
                       .." in directory "..directory) end
   local files = {}
   for filename in lfs.dir(directory) do
      if (filename == filename_would_be) then return true end
   end
   return false
end

function purge_all_except(directory, metadata)
   local keeper = create_richer_preview_filename(metadata)
   for filename in lfs.dir(directory) do
      if filename ~= "." and filename ~= ".." then
         if filename ~= keeper then
            if debug then print("🗑 Binning "..filename) end
            io.popen("rm "..directory.."/"..filename)
         else
            if debug then print("♻ Would keep "..filename) end
         end
      end
   end
end

function render_to_wav(fromfile, tofile)
   -- Because OAuth2 is hard lol.
   if debug then print("🔊 Rendering file "..fromfile) end
   local wavfilename = tofile:gsub('.mp3$', '.wav')
   if debug then print("🔊 Rendering into "..wavfilename) end
   io.popen("nice ffmpeg -n -loglevel warning -i "..fromfile.." "..wavfilename)
end

----------------- utilities -----------------

function parse_metadata(metadata)
   return lunajson.decode(metadata)
end

function create_richer_preview_filename(metadata)
   local filename = metadata['id']
      .."-"..metadata['name'].."-by-"..metadata['username']
      ..'.wav'
   return filename
end

function extract_preview_filename(metadata)
   local filename = metadata['previews']['preview-hq-mp3']:gsub('^.*/', '')
   if debug then print("🗜 preview filename is "..filename) end
   return filename
end

---------- main -----------

function main()
   -- local fp = get_frontpage('frontpage.html')
   local fp = get_frontpage()
   local sound_id = get_featured_sound_id(fp)
   local sound_of_the_day = get_sound_metadata(sound_id)
   print("Today's random sound of the day is "
         ..sound_of_the_day['name'].." by "..sound_of_the_day['username'])

   if sound_already_on_disk(DIRECTORY, sound_of_the_day) then
      if debug then print("⏹ Already got "..sound_of_the_day['name']) end
   else
      if debug then print("▶ Getting random sound of the day.") end
      local tmp_preview_filename = get_sound_preview(sound_of_the_day)
      local rendered_preview_filename = DIRECTORY
         ..create_richer_preview_filename(sound_of_the_day)
      render_to_wav(tmp_preview_filename, rendered_preview_filename)
   end
   purge_all_except(DIRECTORY, sound_of_the_day)
end

---------------------- run things -------------

main()
