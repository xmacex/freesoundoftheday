io       = require 'io'
lfs      = require 'lfs'
lunajson = require 'lunajson'

local API_ENDPOINT = "https://freesound.org/apiv2/"
local API_TOKEN    = "your api token here"
local DIRECTORY    = "../../audio/freesoundoftheday/"

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
   if debug then print(":cd: Downloading preview for "..metadata['name']) end
   local filename = create_filename(metadata)
   download_file(metadata['previews']['preview-hq-mp3'], filename)
   return filename
end

--------------- lower level network connections -------

function download_file(url, filename)
   if debug then print("📡 Downloading file from "..url) end
   io.popen("curl -s "..url.. " -o "..DIRECTORY..filename)
end

function query_api(resource, param)
   -- Just takes a single parameter rather than a table.
   local query_url = API_ENDPOINT..resource.."/"..param.."/"
   local auth_url = query_url.."?token="..API_TOKEN
   if debug then print("🛂 "..auth_url) end
   local response = assert(io.popen("curl -s "..auth_url))
   local content = response:read '*all'
   response:close()
   -- if debug then print("📇 Read metadata "..content) end
   return content
end

----------------- utilities -----------------

function parse_metadata(metadata)
   return lunajson.decode(metadata)
end

function create_filename(metadata)
   local filename = metadata['id']
      .."-"..metadata['name'].."-by-"..metadata['username']
      ..'.mp3'
   return filename
end

function some_sounds_already_on_disk()
   local files = {}
   for filename in lfs.dir(DIRECTORY) do
      if filename ~= "." and filename ~= ".." then
         table.insert(files, filename)
      end
   end
   return (#files ~= 0)
end

function sound_already_on_disk(metadata)
   local filename_would_be = create_filename(metadata)
   if debug then print("🗃 Checking for file "..filename_would_be
                       .." in directory "..DIRECTORY) end

   local files = {}
   for filename in lfs.dir(DIRECTORY) do
      if (filename == filename_would_be) then return true end
   end
   return false
end

------ audio processing ----- because OAuth2 is hard lol ------

function render_to_wav(filename)
   local complete_path = DIRECTORY..filename
   if debug then print("🔊 Rendering file "..complete_path) end
   complete_path_wav = string.gsub(complete_path, "[^.]+$", "wav")
   if debug then print("🔊 Rendering into "..complete_path_wav) end
   io.popen("nice ffmpeg -n -loglevel warning -i "..complete_path.." "..complete_path_wav)
end


---------- main -----------

function main()
   -- local fp = get_frontpage('frontpage.html')

   local fp = get_frontpage()
   local sound_id = get_featured_sound_id(fp)
   local sound_of_the_day = get_sound_metadata(sound_id)
   print("Today's random sound of the day is "
         ..sound_of_the_day['name'].." by "..sound_of_the_day['username'])

   if (not sound_already_on_disk(sound_of_the_day)) then
      if debug then print("▶ Getting random sound of the day.") end
      preview_filename = get_sound_preview(sound_of_the_day)
      render_to_wav(preview_filename)
   else
      if debug then print("⏹ But its today's "..sound_of_the_day['name']) end
   end
end

---------------------- run things -------------

main()
