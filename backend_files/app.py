from flask import Flask, request, jsonify
import yt_dlp

app = Flask(__name__)

# Root route (for browser check)
@app.route('/')
def home():
    return "Video Downloader Backend Running!"

# Download route
@app.route('/download', methods=['POST'])
def download_video():
    data = request.get_json()
    url = data.get("url")

    if not url:
        return jsonify({"error": "No URL provided"}), 400

    try:
        ydl_opts = {
            "format": "best",
            "outtmpl": "%(title)s.%(ext)s"   # save format if downloading
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)  # don’t download, just fetch info
            return jsonify({
                "title": info.get("title"),
                "url": url,
                "status": "ready"
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
