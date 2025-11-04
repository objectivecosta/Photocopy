#!/usr/bin/env python3
"""
Photocopy Python ML Service
Analyzes images using the Moondream2 vision-language model
"""

import json
import sys
import os
import re
from pathlib import Path
import argparse
import logging
from typing import Dict, Any, Optional, List
import time
import traceback

# Add lib directory to Python path for bundled dependencies
current_dir = Path(__file__).parent
lib_dir = current_dir / "lib"
if lib_dir.exists():
    sys.path.insert(0, str(lib_dir))

try:
    from transformers import AutoModelForCausalLM
    from PIL import Image
    import torch
except ImportError as e:
    print(json.dumps({
        "error": f"Failed to import required libraries: {e}",
        "status": "import_error"
    }))
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class PhotocopyMLService:
    def __init__(self, config_path: Optional[str] = None):
        """Initialize the ML service with configuration"""
        self.config = self._load_config(config_path)
        self.model = None
        self.device = None # self.config.get("model", {}).get("device", "mps")
        self._model_loaded = False

    def _load_config(self, config_path: Optional[str]) -> Dict[str, Any]:
        """Load configuration from JSON file"""
        default_config = {
            "pythonVersion": "3.11",
            "architecture": "arm64",
            "model": {
                "name": "moondream2",
                "repository": "vikhyatk/moondream2",
                "trustRemoteCode": True,
                "device": "mps"
            },
            "generationSettings": {
                "temperature": 0.5,
                "maxTokens": 768,
                "topP": 0.3,
                "length": "short"
            },
            "timeout": 60
        }

        if config_path and os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    loaded_config = json.load(f)
                    default_config.update(loaded_config)
            except Exception as e:
                logger.warning(f"Failed to load config from {config_path}: {e}")

        return default_config

    def _load_model(self) -> bool:
        """Load the Moondream2 model"""
        if self._model_loaded:
            return True

        try:
            logger.info("Loading Moondream2 model...")
            model_repo = self.config.get("model", {}).get("repository", "vikhyatk/moondream2")
            trust_remote_code = self.config.get("model", {}).get("trustRemoteCode", True)

            self.model = AutoModelForCausalLM.from_pretrained(
                model_repo,
                revision="2025-06-21",
                trust_remote_code=trust_remote_code,
                dtype=torch.bfloat16,
            )

            self._model_loaded = True
            logger.info("Model loaded successfully")
            return True

        except Exception as e:
            exc_type, exc_obj, exc_tb = sys.exc_info()
            fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
            logger.error(f"Failed to load model: {e} |||| Filename: {fname}")
            logger.error(f"{traceback.format_exc()}")
            return False

    def analyze_image(self, image_path: str, custom_settings: Optional[Dict] = None) -> Dict[str, Any]:
        """Analyze an image and return the caption"""
        start_time = time.time()

        try:
            # Load image
            if not os.path.exists(image_path):
                return {
                    "error": f"Image file not found: {image_path}",
                    "status": "file_error"
                }

            image = Image.open(image_path)
            logger.info(f"Loaded image: {image_path} ({image.size})")

            # Ensure model is loaded
            if not self._load_model():
                return {
                    "error": "Failed to load ML model",
                    "status": "model_error"
                }

            # Get generation settings
            settings = custom_settings or self.config.get("generationSettings", {})
            length = settings.pop("length", "short")

            # Generate caption and tags using query method
            logger.info("Generating analysis...")

            # Generate caption
            caption_prompt = "Describe this image in a concise, natural way."
            caption_result = self.model.query(image, caption_prompt)
            caption = caption_result.get("answer", "").strip()

            # Generate tags as JSON
            tags_prompt = """Analyze this image and return a JSON object with the following structure:
{
  "tags": ["tag1", "tag2", "tag3", ...],
  "objects": ["object1", "object2", ...],
  "scene": "scene description",
  "colors": ["color1", "color2", ...],
  "actions": ["action1", "action2", ...]
}

Focus on the most important and relevant tags. Limit tags to 10-15 items total."""

            tags_result = self.model.query(image, tags_prompt)
            tags_response = tags_result.get("answer", "").strip()

            # Parse the tags response
            try:
                import json
                # Extract JSON from the response (in case there's extra text)
                json_match = re.search(r'\{.*\}', tags_response, re.DOTALL)
                if json_match:
                    tags_data = json.loads(json_match.group())
                    tags = tags_data.get("tags", [])
                    # Include other useful information
                    objects = tags_data.get("objects", [])
                    scene = tags_data.get("scene", "")
                    colors = tags_data.get("colors", [])
                    actions = tags_data.get("actions", [])
                else:
                    # Fallback: extract comma-separated values
                    tags = [tag.strip() for tag in tags_response.split(",") if tag.strip()]
                    objects = []
                    scene = ""
                    colors = []
                    actions = []
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse tags JSON: {tags_response}")
                # Fallback: treat the whole response as comma-separated tags
                tags = [tag.strip() for tag in tags_response.split(",") if tag.strip()]
                objects = []
                scene = ""
                colors = []
                actions = []

            processing_time = time.time() - start_time

            return {
                "status": "success",
                "caption": caption,
                "tags": tags[:15],  # Limit to 15 tags
                "analysis": {
                    "objects": objects,
                    "scene": scene,
                    "colors": colors,
                    "actions": actions
                },
                "processing_time": processing_time,
                "image_path": image_path,
                "image_size": list(image.size),
                "model_info": {
                    "name": self.config.get("model", {}).get("name"),
                    "repository": self.config.get("model", {}).get("repository")
                }
            }

        except Exception as e:
            logger.error(f"Error analyzing image: {e}")
            return {
                "error": str(e),
                "status": "analysis_error",
                "processing_time": time.time() - start_time
            }

    def health_check(self) -> Dict[str, Any]:
        """Perform a health check of the service"""
        
        if not self._load_model():
            return {
                "status": "not_healthy",
                "model_loaded": self._model_loaded,
                "device": self.device,
                "config": self.config
            }
        
        return {
            "status": "healthy",
            "model_loaded": self._model_loaded,
            "device": self.device,
            "config": self.config
        }

def main():
    """Main entry point for the service"""
    parser = argparse.ArgumentParser(description="Photocopy ML Service")
    parser.add_argument("--config", help="Path to configuration file")
    parser.add_argument("--mode", choices=["analyze", "health"], default="analyze",
                       help="Operation mode")
    parser.add_argument("--image", help="Path to image file for analysis")

    args = parser.parse_args()

    # Debug: Print received arguments
    print(f"DEBUG: Received args: mode={args.mode}, image={args.image}, config={args.config}", file=sys.stderr)

    # Initialize service
    service = PhotocopyMLService(args.config)

    if args.mode == "health":
        # Health check mode
        result = service.health_check()
        print(json.dumps(result, indent=2))
        return 0

    elif args.mode == "analyze":
        if not args.image:
            print(json.dumps({
                "error": "Image path required for analysis mode",
                "status": "missing_image"
            }))
            return 1

        # Analysis mode
        print(f"DEBUG: Analyzing image: {args.image}", file=sys.stderr)
        result = service.analyze_image(args.image)
        print(f"DEBUG: Analysis result status: {result.get('status')}", file=sys.stderr)
        if result.get("tags"):
            print(f"DEBUG: Generated tags: {result.get('tags')}", file=sys.stderr)
        print(json.dumps(result, indent=2))
        return 0 if result.get("status") == "success" else 1

    else:
        # Interactive mode - read from stdin
        try:
            # Read JSON input from stdin
            input_data = json.load(sys.stdin)

            if input_data.get("action") == "analyze":
                image_path = input_data.get("image_path")
                custom_settings = input_data.get("settings")

                if not image_path:
                    print(json.dumps({
                        "error": "image_path required",
                        "status": "missing_image_path"
                    }))
                    return 1

                result = service.analyze_image(image_path, custom_settings)
                print(json.dumps(result))
                return 0 if result.get("status") == "success" else 1

            elif input_data.get("action") == "health":
                result = service.health_check()
                print(json.dumps(result))
                return 0

            else:
                print(json.dumps({
                    "error": f"Unknown action: {input_data.get('action')}",
                    "status": "unknown_action"
                }))
                return 1

        except json.JSONDecodeError:
            print(json.dumps({
                "error": "Invalid JSON input",
                "status": "json_error"
            }))
            return 1
        except Exception as e:
            print(json.dumps({
                "error": f"Unexpected error: {e}",
                "status": "unexpected_error"
            }))
            return 1

if __name__ == "__main__":
    sys.exit(main())
