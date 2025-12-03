#!/usr/bin/env python3
"""
Send test events to the Event Ingestion API
Usage: python3 send-test-events.py [num_events]
"""

import sys
import json
import time
import random
from datetime import datetime
import subprocess
import requests
import signal

# Configuration
NAMESPACE = "gamemetrics"
SERVICE = "event-ingestion"
LOCAL_PORT = 8081
NUM_EVENTS = int(sys.argv[1]) if len(sys.argv) > 1 else 10

# Event types and player IDs to rotate through
EVENT_TYPES = ["login", "logout", "level_up", "purchase", "achievement", "game_start", "game_end"]
PLAYER_IDS = ["player-001", "player-002", "player-003", "player-004", "player-005"]

port_forward_process = None

def cleanup():
    """Kill port-forward process on exit"""
    if port_forward_process:
        print("\nCleaning up port-forward...")
        port_forward_process.terminate()
        port_forward_process.wait()
        print("✓ Port-forward stopped")

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    cleanup()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def main():
    global port_forward_process
    
    print("=" * 50)
    print("Sending Test Events to Event Ingestion API")
    print("=" * 50)
    print(f"\nConfiguration:")
    print(f"  Namespace: {NAMESPACE}")
    print(f"  Service: {SERVICE}")
    print(f"  Local port: {LOCAL_PORT}")
    print(f"  Number of events: {NUM_EVENTS}\n")
    
    # Start port-forward
    print("Setting up port-forward...")
    port_forward_process = subprocess.Popen(
        ["kubectl", "port-forward", "-n", NAMESPACE, f"svc/{SERVICE}", f"{LOCAL_PORT}:80"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    print(f"✓ Port-forward started (PID: {port_forward_process.pid})")
    print("Waiting for port-forward to be ready...")
    time.sleep(10)
    
    base_url = f"http://localhost:{LOCAL_PORT}"
    
    # Test health endpoints
    print("\nTesting health endpoints...")
    try:
        live_response = requests.get(f"{base_url}/health/live", timeout=5)
        print(f"  Live: {live_response.json().get('status', 'unknown')}")
        
        ready_response = requests.get(f"{base_url}/health/ready", timeout=5)
        print(f"  Ready: {ready_response.json().get('status', 'unknown')}")
    except Exception as e:
        print(f"  ⚠ Health check failed: {e}")
    
    print(f"\nSending {NUM_EVENTS} test events...\n")
    
    success_count = 0
    fail_count = 0
    
    for i in range(1, NUM_EVENTS + 1):
        # Rotate through event types and player IDs
        event_type = EVENT_TYPES[i % len(EVENT_TYPES)]
        player_id = PLAYER_IDS[i % len(PLAYER_IDS)]
        
        # Create event payload
        payload = {
            "player_id": player_id,
            "game_id": "game-realtime-001",
            "event_type": event_type,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "data": {
                "level": random.randint(1, 100),
                "score": random.randint(0, 10000),
                "session_id": f"session-{random.randint(0, 1000)}"
            }
        }
        
        # Send event
        try:
            response = requests.post(
                f"{base_url}/api/v1/events",
                json=payload,
                timeout=5
            )
            
            if response.status_code in [200, 201, 202]:
                success_count += 1
                print(f"✓ Event {i}: {event_type} for {player_id} (HTTP {response.status_code})")
            else:
                fail_count += 1
                print(f"✗ Event {i}: {event_type} for {player_id} (HTTP {response.status_code})")
                print(f"  Response: {response.text}")
        except Exception as e:
            fail_count += 1
            print(f"✗ Event {i}: {event_type} for {player_id} - Error: {e}")
        
        # Small delay between events
        time.sleep(0.1)
    
    print("\n" + "=" * 50)
    print("Test Results:")
    print(f"  Total events: {NUM_EVENTS}")
    print(f"  Successful: {success_count}")
    print(f"  Failed: {fail_count}")
    print("=" * 50)
    print()
    
    if fail_count == 0:
        print("✓ All events sent successfully!\n")
        print("Next steps:")
        print("  1. Check Kafka topics:")
        print("     kubectl port-forward -n kafka svc/kafka-ui 8080:8080")
        print("     Open http://localhost:8080\n")
        print("  2. Check application logs:")
        print(f"     kubectl logs -n {NAMESPACE} -l app=event-ingestion --tail=50")
    else:
        print("⚠ Some events failed. Check application logs:")
        print(f"  kubectl logs -n {NAMESPACE} -l app=event-ingestion --tail=50")
    
    print()
    cleanup()

if __name__ == "__main__":
    main()
