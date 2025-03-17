#!/usr/bin/lua

local LUA_VERSION  = _VERSION:match("%d+%.%d+")
package.path       = "share/lua/"..LUA_VERSION.."/?.lua;"..package.path
local io           = require 'io'
local lfs          = require 'lfs'
local lunajson     = require 'lunajson'

local API_ENDPOINT = "https://freesound.org/apiv2/"
local API_TOKEN    = "7GpLkaFEHHF4m2zPzhmKyfZEgCP0G1l12VqVGKg7"
local DIRECTORY    = "/home/we/dust/audio/freesoundoftheday/"

local DEBUG        = false
local LOGGING      = true

if DEBUG then DIRECTORY = "/tmp/freesoundoftheday/" end

--------------- network connections -----------------

function get_frontpage(path)
   local content = nil
   if (path ~= nil) then
      log("🗄 Getting frontpage from file.")
      local fd = io.open(path, 'r')
      content = fd:read '*all'
      fd:close()
      log("🗜 Read "..#content.."B frontpage from file.")
   else
      log("📡 Getting frontpage from network.")
      local response = assert(io.popen("curl -s https://freesound.org"))
      content = response:read '*all'
      response:close()
      log("🗜 Read "..#content.."B frontpage from network.")
   end
   return content
end

function get_featured_sound_id(frontpage)
   log("🔐 Looking for sound id.")
   -- assumes it's the first player on the page. Sad.
   -- local pattern = 'class="sample_player_small" id="(%d+)"'
   local pattern = 'Random sound of the day.-data.sound.id="(%d+)"'
   local featured_sound_id = string.match(frontpage, pattern)
   log("🔑 Found sound id "..featured_sound_id)
   return featured_sound_id
end

function get_sound_metadata(sound_id)
   log("📡 Getting metadata for sound id "..sound_id)
   local metadata = query_api("sounds", sound_id)
   local parsed   = parse_metadata(metadata)
   return parsed
end

function get_sound_preview(metadata)
   log("💿 Downloading preview for "..metadata['name'])
   local filename = extract_preview_filename(metadata)
   local complete_path = "/tmp/"..filename
   download_file(metadata['previews']['preview-hq-mp3'], complete_path)
   return complete_path
end

--------------- lower level network connections -------

function download_file(url, filename)
   log("📡 Downloading file from "..url)
   -- io.popen("curl -s "..url.. " -o "..DIRECTORY..filename)
   io.popen("curl -s "..url.." -o "..filename)
end

function query_api(resource, param)
   -- Just takes a single parameter rather than a table.
   local query_url = API_ENDPOINT..resource.."/"..param.."/"
   local auth_url = query_url.."?token="..API_TOKEN
   log("🛂 "..auth_url)
   local response = assert(io.popen("curl -s "..auth_url..";sync"))
   local content = response:read '*all'
   response:close()
   -- log("📇 Read metadata "..content)
   log("📇 Read "..#content.. "B of metadata ")
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
   log("🗃 Checking for file "..filename_would_be
                       .." in directory "..directory)
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
            log("🗑 Binning "..filename)
            if not DEBUG then io.popen("rm "..directory.."/"..'"'..filename..'"') end
         else
            log("♻ Would keep "..filename)
         end
      end
   end
end

function render_to_wav(fromfile, tofile)
   -- Because OAuth2 is hard lol.
   log("🔊 Rendering file "..fromfile)
   local wavfilename = tofile:gsub('.mp3$', '.wav')
   log("🔊 Rendering into "..wavfilename)
   io.popen("nice ffmpeg -n -loglevel warning -i "..fromfile.." '"..wavfilename.."'")
end

----------------- utilities -----------------

function log(message)
   if LOGGING then print(message) end
end

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
   log("🗜 preview filename is "..filename)
   return filename
end

---------- main -----------

function main()
   if DEBUG then print("🔍 Debugging on") end
   -- local fp = get_frontpage('frontpage.html')
   local fp = get_frontpage()
   local sound_id = get_featured_sound_id(fp)
   local sound_of_the_day = get_sound_metadata(sound_id)
   print("👂 Today's random sound of the day is "
         ..sound_of_the_day['name'].." by "..sound_of_the_day['username'])

   if sound_already_on_disk(DIRECTORY, sound_of_the_day) then
      log("⏹ Already got "..sound_of_the_day['name'])
   else
      log("▶ Getting random sound of the day.")
      local tmp_preview_filename = get_sound_preview(sound_of_the_day)
      local rendered_preview_filename = DIRECTORY
         ..create_richer_preview_filename(sound_of_the_day)
      render_to_wav(tmp_preview_filename, rendered_preview_filename)
   end
   purge_all_except(DIRECTORY, sound_of_the_day)
end

---------------------- run things -------------

main()
