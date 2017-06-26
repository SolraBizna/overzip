if #arg ~= 2 or arg[1] == arg[2] then
   print[[
Usage: overzip input.zip output.zip
Input and output must not be the same
This utility AGGRESSIVELY DISCARDS EXTRA INFORMATION, MUST NOT BE USED ON
UNTRUSTED ARCHIVES, and is KNOWN TO BE DEFICIENT IN ITS HANDLING OF ZIPFILES.]]
   os.exit(1)
end

local function out32(f, u)
   f:write(string.char(bit32.band(u,255),
                       bit32.band(bit32.rshift(u,8),255),
                       bit32.band(bit32.rshift(u,16),255),
                       bit32.rshift(u,24)))
end

local function out16(f, u)
   f:write(string.char(bit32.band(u,255),
                       bit32.rshift(u,8)))
end

local function in32(f)
   local x = assert(f:read(4))
   return x:byte(1) + bit32.lshift(x:byte(2),8) + bit32.lshift(x:byte(3),16)
      + bit32.lshift(x:byte(4),24), x
end

local function in16(f)
   local x = assert(f:read(2))
   return x:byte(1) + bit32.lshift(x:byte(2),8), x
end

local infile = assert(io.open(arg[1], "rb"))
-- get length of input file
local inlength = assert(infile:seek("end",0))

-- scan for end of central directory
local cd_offset,cd_entry_count
local EOCD_FOOTER_SIZE = 22
for comment_length=0,65535 do
   if EOCD_FOOTER_SIZE + comment_length > inlength then
      -- zip file not long enough to contain such a thing
      break
   end
   assert(infile:seek("end",-(EOCD_FOOTER_SIZE+comment_length)))
   if in32(infile) ~= 0x06054b50 then goto continue end
   -- ignore disk numbers
   in16(infile)
   in16(infile)
   -- get entry count (and don't bother looking at multi-disk archives)
   local candidate_entry_count = in16(infile)
   if in16(infile) ~= candidate_entry_count then goto continue end
   -- ignore CD size
   in32(infile)
   local candidate_cd_offset = in32(infile)
   if in16(infile) == comment_length then
      cd_offset = candidate_cd_offset
      cd_entry_count = candidate_entry_count
      break
   end
   ::continue::
end
if not cd_offset then
   print("Not a single-disk Zip archive")
   os.exit(1)
end

local entries = {}
local very_similar_files = {}
assert(infile:seek("set",cd_offset))
for n=1,cd_entry_count do
   assert(in32(infile) == 0x02014b50, "Invalid zip archive")
   local madeby = infile:read(2) -- ignore!
   -- version needed to extract, bits, compression method
   local first_bits = infile:read(6)
   local second_bits = infile:read(4) -- mtime/mdate
   local crc_bits = infile:read(4) -- CRC32 of uncompressed data
   local compressed_size,compressed_size_bits = in32(infile)
   local uncompressed_size_bits = infile:read(4)
   local filename_length = in16(infile)
   local extra_length = in16(infile)
   local comment_length = in16(infile)
   in16(infile) -- disk number start
   in16(infile) -- internal file attributes
   in32(infile) -- external file attributes
   local local_header_offset = in32(infile)
   local filename = assert(infile:read(filename_length))
   infile:seek("cur", extra_length + comment_length)
   local ccookie = first_bits..crc_bits..compressed_size_bits..uncompressed_size_bits
   local ent = {
      headerbits=first_bits..second_bits..crc_bits..compressed_size_bits..uncompressed_size_bits,
      compressed_size=compressed_size,
      header_offset=local_header_offset,
      filename=filename,
   }
   if ent.filename:sub(-1,-1) == "/" then
      -- is a directory
      if uncompressed_size_bits ~= "\0\0\0\0" then
         print("Directory contains data: "..ent.filename)
      end
   else
      -- is a file
      if not very_similar_files[ccookie] then
         very_similar_files[ccookie] = {ent}
      else
         table.insert(very_similar_files[ccookie], ent)
      end
   end
   entries[n] = ent
end
for n=1,#entries do
   local ent = entries[n]
   assert(infile:seek("set",ent.header_offset))
   assert(in32(infile) == 0x04034b50, "Invalid zip archive")
   assert(infile:read(22) == ent.headerbits, "Inconsistent zip archive")
   local filename_length = in16(infile)
   local xt_length = in16(infile)
   local filename = assert(infile:read(filename_length))
   if filename_length > 0 and filename ~= ent.filename then
      print("Inconsistent filename: "..ent.filename.." in CD, "..filename.." in local header (using CD name)")
   end
   ent.data_start = assert(infile:seek("cur",xt_length))
end
local dupes = 0
for k,v in pairs(very_similar_files) do
   if #v > 1 then
      local datamap = {}
      for i,ent in ipairs(v) do
         assert(infile:seek("set",ent.data_start))
         local data = assert(infile:read(ent.compressed_size))
         if datamap[data] then
            -- print(ent.filename.." == "..datamap[data].filename)
            dupes = dupes + 1
            ent.dup = datamap[data]
         else
            datamap[data] = ent
         end
      end
   end
end
local outfile = assert(io.open(arg[2],"wb"))
for i,ent in ipairs(entries) do
   if ent.dup then
      ent.header_offset = ent.dup.header_offset
   else
      ent.header_offset = outfile:seek("cur",0)
      out32(outfile, 0x04034b50)
      outfile:write(ent.headerbits)
      outfile:write("\0\0\0\0") -- no filename, no extra data
      assert(infile:seek("set",ent.data_start))
      outfile:write(assert(infile:read(ent.compressed_size)))
   end
end
infile:close()
cd_offset = assert(outfile:seek("cur",0))
for i,ent in ipairs(entries) do
   out32(outfile, 0x02014b50)
   outfile:write("\20\0") -- no extra attributes, version 2.0 zipfile
   outfile:write(ent.headerbits)
   out16(outfile, #ent.filename) -- filename length
   outfile:write("\0\0\0\0\0\0\0\0\0\0\0\0") -- xt/com length, disk#, attrs
   out32(outfile, ent.header_offset)
   outfile:write(ent.filename)
end
local cd_end = assert(outfile:seek("cur",0))
out32(outfile, 0x06054b50)
outfile:write("\0\0\0\0") -- disk#
out16(outfile, #entries)
out16(outfile, #entries)
out32(outfile, cd_end-cd_offset)
out32(outfile, cd_offset)
local COMMENT = "victim of overzip"
out16(outfile, #COMMENT)
outfile:write(COMMENT)
local outlength = outfile:seek("cur",0)
outfile:close()
print(("Output ratio: %.1f%% (folded %i dupe%s)")
      :format(outlength*100/inlength, dupes, dupes == 1 and "" or "s"))
