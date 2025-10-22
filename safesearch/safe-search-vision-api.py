#!/usr/bin/env python3
"""
Script to perform Safe Search analysis on MP4 video frames using Google Cloud Vision API
Useful for analyzing AGV (Automated Guided Vehicle) recorded videos for safety compliance
"""

import os
import cv2
import argparse
import json
from typing import List, Dict, Any
from google.cloud import vision
from google.cloud.vision import ImageAnnotatorClient
import numpy as np
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class VideoSafeSearchAnalyzer:
    """Analyzes video frames for inappropriate content using Cloud Vision API"""
    
    def __init__(self, credentials_path: str = None):
        """
        Initialize the analyzer with Google Cloud credentials
        
        Args:
            credentials_path: Path to service account JSON file (optional if env var is set)
        """
        if credentials_path:
            os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = credentials_path
            
        self.client = vision.ImageAnnotatorClient()
        
    def extract_frames(self, video_path: str, interval_seconds: float = 1.0) -> List[np.ndarray]:
        """
        Extract frames from video at specified intervals
        
        Args:
            video_path: Path to the MP4 file
            interval_seconds: Time interval between frame extractions
            
        Returns:
            List of frames as numpy arrays
        """
        frames = []
        cap = cv2.VideoCapture(video_path)
        
        if not cap.isOpened():
            raise ValueError(f"Error opening video file: {video_path}")
            
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_interval = int(fps * interval_seconds)
        frame_count = 0
        
        logger.info(f"Video FPS: {fps}, extracting every {frame_interval} frames")
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
                
            if frame_count % frame_interval == 0:
                frames.append(frame)
                logger.debug(f"Extracted frame {frame_count}")
                
            frame_count += 1
            
        cap.release()
        logger.info(f"Extracted {len(frames)} frames from video")
        return frames
    
    def analyze_frame_safety(self, frame: np.ndarray) -> Dict[str, Any]:
        """
        Analyze a single frame for safe search detection
        
        Args:
            frame: Video frame as numpy array
            
        Returns:
            Dictionary containing safe search results
        """
        # Convert frame to bytes
        _, buffer = cv2.imencode('.jpg', frame)
        image_bytes = buffer.tobytes()
        
        # Create vision API image object
        image = vision.Image(content=image_bytes)
        
        # Perform safe search detection
        response = self.client.safe_search_detection(image=image)
        safe_search = response.safe_search_annotation
        
        # Map likelihood levels to readable strings
        likelihood_names = ['UNKNOWN', 'VERY_UNLIKELY', 'UNLIKELY', 'POSSIBLE', 'LIKELY', 'VERY_LIKELY']
        
        return {
            'adult': likelihood_names[safe_search.adult],
            'spoof': likelihood_names[safe_search.spoof],
            'medical': likelihood_names[safe_search.medical],
            'violence': likelihood_names[safe_search.violence],
            'racy': likelihood_names[safe_search.racy]
        }
    
    def analyze_video(self, video_path: str, interval_seconds: float = 1.0,
                     save_flagged_frames: bool = False, output_dir: str = None) -> Dict[str, Any]:
        """
        Analyze entire video for safe search content
        
        Args:
            video_path: Path to the MP4 file
            interval_seconds: Time interval between frame analysis
            save_flagged_frames: Whether to save frames with potential issues
            output_dir: Directory to save flagged frames
            
        Returns:
            Dictionary containing analysis results
        """
        if not os.path.exists(video_path):
            raise FileNotFoundError(f"Video file not found: {video_path}")
            
        logger.info(f"Starting analysis of video: {video_path}")
        
        # Extract frames
        frames = self.extract_frames(video_path, interval_seconds)
        
        # Prepare output directory if needed
        if save_flagged_frames and output_dir:
            os.makedirs(output_dir, exist_ok=True)
            
        # Analyze each frame
        results = {
            'video_path': video_path,
            'total_frames_analyzed': len(frames),
            'interval_seconds': interval_seconds,
            'timestamp': datetime.now().isoformat(),
            'frame_results': [],
            'summary': {
                'max_adult': 'VERY_UNLIKELY',
                'max_violence': 'VERY_UNLIKELY',
                'max_medical': 'VERY_UNLIKELY',
                'max_racy': 'VERY_UNLIKELY',
                'max_spoof': 'VERY_UNLIKELY',
                'flagged_frames': []
            }
        }
        
        likelihood_levels = {
            'UNKNOWN': 0, 'VERY_UNLIKELY': 1, 'UNLIKELY': 2,
            'POSSIBLE': 3, 'LIKELY': 4, 'VERY_LIKELY': 5
        }
        
        for idx, frame in enumerate(frames):
            logger.info(f"Analyzing frame {idx + 1}/{len(frames)}")
            
            try:
                frame_result = self.analyze_frame_safety(frame)
                frame_result['frame_index'] = idx
                frame_result['timestamp_seconds'] = idx * interval_seconds
                results['frame_results'].append(frame_result)
                
                # Update summary with maximum values
                for key in ['adult', 'violence', 'medical', 'racy', 'spoof']:
                    if likelihood_levels[frame_result[key]] > likelihood_levels[results['summary'][f'max_{key}']]:
                        results['summary'][f'max_{key}'] = frame_result[key]
                
                # Check if frame should be flagged (POSSIBLE or higher for critical categories)
                is_flagged = any([
                    likelihood_levels[frame_result['adult']] >= 3,
                    likelihood_levels[frame_result['violence']] >= 3,
                    likelihood_levels[frame_result['racy']] >= 3
                ])
                
                if is_flagged:
                    results['summary']['flagged_frames'].append({
                        'frame_index': idx,
                        'timestamp_seconds': idx * interval_seconds,
                        'reasons': frame_result
                    })
                    
                    # Save flagged frame if requested
                    if save_flagged_frames and output_dir:
                        frame_filename = f"flagged_frame_{idx:04d}.jpg"
                        frame_path = os.path.join(output_dir, frame_filename)
                        cv2.imwrite(frame_path, frame)
                        logger.warning(f"Flagged frame saved: {frame_path}")
                        
            except Exception as e:
                logger.error(f"Error analyzing frame {idx}: {str(e)}")
                results['frame_results'].append({
                    'frame_index': idx,
                    'error': str(e)
                })
                
        return results
    
    def generate_report(self, results: Dict[str, Any], output_file: str = None) -> str:
        """
        Generate a human-readable report from analysis results
        
        Args:
            results: Analysis results dictionary
            output_file: Optional file path to save the report
            
        Returns:
            Report as string
        """
        report = []
        report.append("=" * 60)
        report.append("VIDEO SAFE SEARCH ANALYSIS REPORT")
        report.append("=" * 60)
        report.append(f"Video: {results['video_path']}")
        report.append(f"Analysis Date: {results['timestamp']}")
        report.append(f"Frames Analyzed: {results['total_frames_analyzed']}")
        report.append(f"Sampling Interval: {results['interval_seconds']} seconds")
        report.append("")
        
        report.append("SUMMARY")
        report.append("-" * 40)
        report.append(f"Maximum Adult Content: {results['summary']['max_adult']}")
        report.append(f"Maximum Violence: {results['summary']['max_violence']}")
        report.append(f"Maximum Medical: {results['summary']['max_medical']}")
        report.append(f"Maximum Racy Content: {results['summary']['max_racy']}")
        report.append(f"Maximum Spoof: {results['summary']['max_spoof']}")
        report.append("")
        
        if results['summary']['flagged_frames']:
            report.append(f"⚠️  FLAGGED FRAMES: {len(results['summary']['flagged_frames'])}")
            report.append("-" * 40)
            for flagged in results['summary']['flagged_frames']:
                report.append(f"Frame {flagged['frame_index']} at {flagged['timestamp_seconds']:.1f}s:")
                for key, value in flagged['reasons'].items():
                    if key not in ['frame_index', 'timestamp_seconds']:
                        report.append(f"  - {key}: {value}")
                report.append("")
        else:
            report.append("✓ No concerning content detected")
            
        report_text = "\n".join(report)
        
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report_text)
            logger.info(f"Report saved to: {output_file}")
            
        return report_text


def main():
    parser = argparse.ArgumentParser(
        description='Analyze MP4 video for inappropriate content using Google Cloud Vision API'
    )
    parser.add_argument('video_path', help='Path to the MP4 video file')
    parser.add_argument('--credentials', help='Path to Google Cloud service account JSON file')
    parser.add_argument('--interval', type=float, default=1.0,
                       help='Interval in seconds between frame analysis (default: 1.0)')
    parser.add_argument('--save-flagged', action='store_true',
                       help='Save flagged frames to disk')
    parser.add_argument('--output-dir', default='flagged_frames',
                       help='Directory to save flagged frames (default: flagged_frames)')
    parser.add_argument('--json-output', help='Path to save JSON results')
    parser.add_argument('--report-output', help='Path to save text report')
    
    args = parser.parse_args()
    
    try:
        # Initialize analyzer
        analyzer = VideoSafeSearchAnalyzer(credentials_path=args.credentials)
        
        # Analyze video
        results = analyzer.analyze_video(
            video_path=args.video_path,
            interval_seconds=args.interval,
            save_flagged_frames=args.save_flagged,
            output_dir=args.output_dir
        )
        
        # Save JSON results if requested
        if args.json_output:
            with open(args.json_output, 'w') as f:
                json.dump(results, f, indent=2)
            logger.info(f"JSON results saved to: {args.json_output}")
            
        # Generate and print report
        report = analyzer.generate_report(results, args.report_output)
        print("\n" + report)
        
        # Exit with appropriate code
        if results['summary']['flagged_frames']:
            logger.warning(f"Analysis complete. {len(results['summary']['flagged_frames'])} frames flagged.")
            exit(1)
        else:
            logger.info("Analysis complete. No concerning content detected.")
            exit(0)
            
    except Exception as e:
        logger.error(f"Error during analysis: {str(e)}")
        exit(1)


if __name__ == "__main__":
    main()
