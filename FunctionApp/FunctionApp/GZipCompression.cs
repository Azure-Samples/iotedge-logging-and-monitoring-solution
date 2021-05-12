using System.IO;
using System.Text;
using System.IO.Compression;

namespace FunctionApp
{
    public class GZipCompression
    {
        public static string Decompress(Stream compressedStream)
        {
            using GZipStream decompressionStream = new GZipStream(compressedStream, CompressionMode.Decompress);
            StreamReader reader = new StreamReader(decompressionStream);
            string decompressedText = reader.ReadToEnd();

            return decompressedText;
        }

        public static string Decompress(byte[] compressedBytes)
        {
            using Stream compressedStream = new MemoryStream(compressedBytes);
            using GZipStream decompressionStream = new GZipStream(compressedStream, CompressionMode.Decompress);
            using MemoryStream resultStream = new MemoryStream();
            decompressionStream.CopyTo(resultStream);

            byte[] decompressedBytes = resultStream.ToArray();
            string decompressedText = Encoding.UTF8.GetString(decompressedBytes);

            return decompressedText;
        }
    }
}
