import json
from whisper_service import transcribe
from transformer_parser import parse_with_transformer
from tts_service import speak_command_result


def process_voice_command(audio_file, speak_reply=True):
    """Full pipeline: Audio file -> Whisper -> Transformer Parser -> Pocket TTS reply."""
    # Step 1: Speech to Text
    text = transcribe(audio_file).strip()

    # Step 2: Text to Structured JSON
    parsed = parse_with_transformer(text)

    # Step 3: Speak Confirmation Back to User
    if speak_reply:
        reply = speak_command_result(parsed)
        parsed["assistant_reply"] = reply

    return parsed


if __name__ == "__main__":
    audio_file = "audio/Task1.wav"

    print(f"\nProcessing audio: {audio_file}")
    result = process_voice_command(audio_file, speak_reply=True)

    print("\nWHISPER TRANSCRIPTION:")
    print(result["raw_text"])

    print("\nPARSED COMMAND (JSON):")
    print(json.dumps(result, indent=4))