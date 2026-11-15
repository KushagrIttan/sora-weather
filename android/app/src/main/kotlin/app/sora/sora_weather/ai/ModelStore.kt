package app.sora.sora_weather.ai

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CancellationException

data class ModelSpec(
    val id: String,
    val name: String,
    val repository: String,
    val revision: String,
    val filename: String,
    val bytes: Long,
    val sha256: String,
    val runtime: String,
    val contextTokens: Int,
    val maxOutputTokens: Int,
    val reserveBytes: Long,
) {
    val downloadUrl: String
        get() = "https://huggingface.co/$repository/resolve/$revision/$filename"
}

/** Only owns one model directory; never traverses application or shared storage. */
class ModelStore(private val directory: File, val spec: ModelSpec) {
    val modelFile get() = File(directory, spec.filename)
    val partialFile get() = File(directory, "${spec.filename}.part")
    val isInstalled get() = modelFile.isFile && modelFile.length() == spec.bytes
    val partialBytes get() = partialFile.takeIf { it.isFile }?.length() ?: 0L

    fun verify(file: File = modelFile): Boolean {
        if (!file.isFile || file.length() != spec.bytes) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(256 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == spec.sha256
    }

    /** Range resumes against an immutable revision. A full download is hashed
     * before an atomic rename in the same directory, avoiding a second copy. */
    fun install(
        availableBytes: () -> Long,
        cancelled: () -> Boolean,
        progress: (Long, Long) -> Unit,
        openConnection: () -> HttpURLConnection = {
            URL(spec.downloadUrl).openConnection() as HttpURLConnection
        },
    ) {
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create model directory." }
        if (isInstalled && verify()) return
        if (partialBytes > spec.bytes) partialFile.delete()
        val remaining = spec.bytes - partialBytes
        check(availableBytes() >= remaining + spec.reserveBytes) {
            "Free more storage first. The model needs 328 MiB plus 1 GiB of free headroom."
        }
        if (cancelled()) throw CancellationException("Download paused.")
        if (partialBytes < spec.bytes) {
            val connection = openConnection()
            try {
                connection.connectTimeout = 15_000
                connection.readTimeout = 15_000
                connection.setRequestProperty("Accept-Encoding", "identity")
                val offset = partialBytes
                if (offset > 0) connection.setRequestProperty("Range", "bytes=$offset-")
                val code = connection.responseCode
                if (code != 200 && code != 206) throw IOException("Model download returned HTTP $code.")
                if (code == 206) {
                    val range = connection.getHeaderField("Content-Range") ?: ""
                    check(range.startsWith("bytes $offset-")) { "Invalid resumed download range." }
                }
                // A server may ignore Range. Restart, rather than append duplicates.
                var written = if (code == 206) offset else 0L
                RandomAccessFile(partialFile, "rw").use { output ->
                    output.setLength(written)
                    output.seek(written)
                    progress(written, spec.bytes)
                    connection.inputStream.buffered().use { input ->
                        val buffer = ByteArray(256 * 1024)
                        var sinceSpaceCheck = 0L
                        while (true) {
                            if (cancelled()) throw CancellationException("Download paused.")
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (written + count > spec.bytes) throw IOException("Unexpected model size.")
                            output.write(buffer, 0, count)
                            written += count
                            sinceSpaceCheck += count
                            if (sinceSpaceCheck >= 8 * 1024 * 1024) {
                                check(availableBytes() >= spec.reserveBytes + (spec.bytes - written)) {
                                    "Storage is running low. Download paused."
                                }
                                sinceSpaceCheck = 0
                            }
                            progress(written, spec.bytes)
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
        if (cancelled()) throw CancellationException("Download paused.")
        check(availableBytes() >= spec.reserveBytes) { "Free more storage before finishing model installation." }
        if (!verify(partialFile)) {
            // A short response can resume. A complete but corrupt file cannot.
            if (partialBytes == spec.bytes) partialFile.delete()
            throw IOException("Model verification failed. Resume or retry the download.")
        }
        check(partialFile.renameTo(modelFile)) { "Could not finish installing the model." }
    }

    fun remove() {
        check(!modelFile.exists() || modelFile.delete()) { "Could not remove the model." }
        check(!partialFile.exists() || partialFile.delete()) { "Could not remove the partial download." }
    }
}
