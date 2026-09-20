--[[
Raw DEFLATE decompression through the zlib KOReader already ships.

ffi/zlib only exposes zlib_uncompress(), which needs a complete zlib stream
(header and Adler-32 trailer). dictzip chunks are bare deflate streams cut
with Z_FULL_FLUSH, so they need inflateInit2() with negative windowBits.
]]

local ffi = require("ffi")

local Z_OK = 0
local Z_STREAM_END = 1
local Z_SYNC_FLUSH = 2
local Z_BUF_ERROR = -5
local RAW_WINDOW_BITS = -15

local libz
local available = pcall(function()
	-- The struct gets a private name so it can never clash with another
	-- declaration; the function prototypes are the standard zlib ones.
	ffi.cdef([[
	typedef struct dictionaryexplorer_z_stream {
		const uint8_t *next_in;
		unsigned int avail_in;
		unsigned long total_in;
		uint8_t *next_out;
		unsigned int avail_out;
		unsigned long total_out;
		const char *msg;
		void *state;
		void *zalloc;
		void *zfree;
		void *opaque;
		int data_type;
		unsigned long adler;
		unsigned long reserved;
	} dictionaryexplorer_z_stream;
	int inflateInit2_(dictionaryexplorer_z_stream *strm, int windowBits, const char *version, int stream_size);
	int inflate(dictionaryexplorer_z_stream *strm, int flush);
	int inflateEnd(dictionaryexplorer_z_stream *strm);
	const char *zlibVersion(void);
	]])
end)

local function getLib()
	if libz == nil then
		local ok, lib = pcall(function()
			return ffi.loadlib("z", 1)
		end)
		libz = ok and lib or false
	end
	return libz
end

local Inflate = {}

--- Inflates one raw deflate chunk.
-- @string data compressed bytes
-- @int expected_size upper bound for the decompressed size
-- @treturn string decompressed bytes, or nil and an error message
function Inflate.raw(data, expected_size)
	local lib = getLib()
	if not available or not lib then
		return nil, "zlib is not available"
	end

	local stream = ffi.new("dictionaryexplorer_z_stream")
	local init = lib.inflateInit2_(stream, RAW_WINDOW_BITS, lib.zlibVersion(), ffi.sizeof(stream))
	if init ~= Z_OK then
		return nil, "inflateInit2 failed: " .. init
	end

	local out = ffi.new("uint8_t[?]", expected_size)
	stream.next_in = data
	stream.avail_in = #data
	stream.next_out = out
	stream.avail_out = expected_size

	-- A dictzip chunk ends with a flush marker rather than a final block, so
	-- running out of input (Z_BUF_ERROR) after producing output is normal.
	local status = lib.inflate(stream, Z_SYNC_FLUSH)
	local produced = tonumber(stream.total_out)
	lib.inflateEnd(stream)

	if status ~= Z_OK and status ~= Z_STREAM_END and not (status == Z_BUF_ERROR and produced > 0) then
		return nil, "inflate failed: " .. status
	end
	return ffi.string(out, produced)
end

return Inflate
