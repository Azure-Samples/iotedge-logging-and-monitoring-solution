using System;
using System.IO.Compression;
using System.Collections.Generic;
using System.IO;
using Microsoft.Extensions.Logging;

namespace FunctionApp
{
    public class GZipCompression
    {
        private ILogger _log;

        public GZipCompression(ILogger log)
        {
            this._log = log;
        }

        public Stream Decompress(Stream compressedStream)
        {
            try
            {
                Stream decompressedStream = new MemoryStream();
                using (GZipStream decompressionStream = new GZipStream(compressedStream, CompressionMode.Decompress))
                {
                    decompressionStream.CopyTo(decompressedStream);
                }

                return decompressedStream;
            }
            catch (Exception e)
            {
                this._log.LogError(e.ToString());
                return null;
            }
        }
    }
}
