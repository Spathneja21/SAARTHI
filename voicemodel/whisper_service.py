from transformers import pipeline

print("Loading Whisper model...")

whisper = pipeline(
    "automatic-speech-recognition",
    model="openai/whisper-small"
)

print("Whisper loaded successfully!")


def transcribe(audio_file):
    result = whisper(
        audio_file,
        generate_kwargs={"language": "en", "task": "transcribe"}
    )
    return result["text"]