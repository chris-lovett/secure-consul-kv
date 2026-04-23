#!/usr/bin/env python3
"""
Consul KV Client Example for Python
Demonstrates how to interact with Consul KV from a Python application
"""

import os
import json
import consul
from typing import Optional, Dict, Any

class ConsulKVClient:
    """
    A simple Consul KV client for team-based access
    """
    
    def __init__(
        self,
        host: str = "consul.example.com",
        port: int = 8500,
        token: Optional[str] = None,
        namespace: Optional[str] = None,
        scheme: str = "https",
        verify: bool = True
    ):
        """
        Initialize Consul KV client
        
        Args:
            host: Consul server hostname
            port: Consul server port
            token: ACL token for authentication
            namespace: Consul namespace (Enterprise)
            scheme: http or https
            verify: Verify SSL certificates
        """
        self.namespace = namespace or os.getenv("CONSUL_NAMESPACE", "default")
        self.token = token or os.getenv("CONSUL_HTTP_TOKEN")
        
        if not self.token:
            raise ValueError("Consul token is required. Set CONSUL_HTTP_TOKEN or pass token parameter")
        
        self.client = consul.Consul(
            host=host,
            port=port,
            token=self.token,
            scheme=scheme,
            verify=verify,
            namespace=self.namespace
        )
        
        print(f"✓ Connected to Consul at {scheme}://{host}:{port}")
        print(f"✓ Using namespace: {self.namespace}")
    
    def put(self, key: str, value: Any) -> bool:
        """
        Write a value to Consul KV
        
        Args:
            key: KV key path
            value: Value to store (will be JSON-encoded if dict/list)
        
        Returns:
            True if successful, False otherwise
        """
        try:
            # Convert dict/list to JSON string
            if isinstance(value, (dict, list)):
                value = json.dumps(value)
            
            success = self.client.kv.put(key, value)
            
            if success:
                print(f"✓ Wrote to {key}")
                return True
            else:
                print(f"✗ Failed to write to {key}")
                return False
                
        except Exception as e:
            print(f"✗ Error writing to {key}: {e}")
            return False
    
    def get(self, key: str, decode_json: bool = True) -> Optional[Any]:
        """
        Read a value from Consul KV
        
        Args:
            key: KV key path
            decode_json: Attempt to decode value as JSON
        
        Returns:
            Value from KV store, or None if not found
        """
        try:
            index, data = self.client.kv.get(key)
            
            if data is None:
                print(f"✗ Key not found: {key}")
                return None
            
            value = data['Value'].decode('utf-8')
            
            # Try to decode as JSON if requested
            if decode_json:
                try:
                    value = json.loads(value)
                except json.JSONDecodeError:
                    pass  # Return as string if not valid JSON
            
            print(f"✓ Read from {key}")
            return value
            
        except Exception as e:
            print(f"✗ Error reading from {key}: {e}")
            return None
    
    def delete(self, key: str, recurse: bool = False) -> bool:
        """
        Delete a key from Consul KV
        
        Args:
            key: KV key path
            recurse: Delete all keys with this prefix
        
        Returns:
            True if successful, False otherwise
        """
        try:
            success = self.client.kv.delete(key, recurse=recurse)
            
            if success:
                action = "recursively deleted" if recurse else "deleted"
                print(f"✓ {action.capitalize()} {key}")
                return True
            else:
                print(f"✗ Failed to delete {key}")
                return False
                
        except Exception as e:
            print(f"✗ Error deleting {key}: {e}")
            return False
    
    def list_keys(self, prefix: str) -> list:
        """
        List all keys with a given prefix
        
        Args:
            prefix: Key prefix to search for
        
        Returns:
            List of keys
        """
        try:
            index, keys = self.client.kv.get(prefix, keys=True)
            
            if keys is None:
                print(f"✗ No keys found with prefix: {prefix}")
                return []
            
            print(f"✓ Found {len(keys)} keys with prefix: {prefix}")
            return keys
            
        except Exception as e:
            print(f"✗ Error listing keys: {e}")
            return []
    
    def watch(self, key: str, callback, interval: int = 5):
        """
        Watch a key for changes and call callback when it changes
        
        Args:
            key: KV key to watch
            callback: Function to call when key changes
            interval: Check interval in seconds
        """
        import time
        
        print(f"👁 Watching {key} for changes...")
        last_index = None
        
        try:
            while True:
                index, data = self.client.kv.get(key, index=last_index)
                
                if index != last_index and last_index is not None:
                    print(f"🔔 Change detected in {key}")
                    if data:
                        value = data['Value'].decode('utf-8')
                        try:
                            value = json.loads(value)
                        except json.JSONDecodeError:
                            pass
                        callback(key, value)
                
                last_index = index
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print(f"\n✓ Stopped watching {key}")


def example_usage():
    """
    Example usage of the ConsulKVClient
    """
    
    # Initialize client
    # Token and namespace can be set via environment variables:
    # export CONSUL_HTTP_TOKEN="your-token-here"
    # export CONSUL_NAMESPACE="AIT-001"
    
    client = ConsulKVClient(
        host="consul.example.com",
        port=8500,
        scheme="https"
    )
    
    # Example 1: Write configuration
    print("\n=== Example 1: Write Configuration ===")
    config = {
        "environment": "production",
        "port": 8080,
        "debug": False,
        "database": {
            "host": "db.example.com",
            "port": 5432,
            "name": "myapp"
        }
    }
    client.put("AIT-001/config/app.json", config)
    
    # Example 2: Read configuration
    print("\n=== Example 2: Read Configuration ===")
    retrieved_config = client.get("AIT-001/config/app.json")
    print(f"Retrieved config: {json.dumps(retrieved_config, indent=2)}")
    
    # Example 3: Write simple values
    print("\n=== Example 3: Write Simple Values ===")
    client.put("AIT-001/config/version", "1.0.0")
    client.put("AIT-001/config/feature-flags/new-ui", "true")
    
    # Example 4: List keys
    print("\n=== Example 4: List Keys ===")
    keys = client.list_keys("AIT-001/config/")
    for key in keys:
        print(f"  - {key}")
    
    # Example 5: Read simple value
    print("\n=== Example 5: Read Simple Value ===")
    version = client.get("AIT-001/config/version", decode_json=False)
    print(f"Version: {version}")
    
    # Example 6: Delete a key
    print("\n=== Example 6: Delete Key ===")
    client.delete("AIT-001/config/feature-flags/new-ui")
    
    # Example 7: Watch for changes (commented out - runs indefinitely)
    # print("\n=== Example 7: Watch for Changes ===")
    # def on_change(key, value):
    #     print(f"Config changed: {value}")
    # 
    # client.watch("AIT-001/config/app.json", on_change)


if __name__ == "__main__":
    # Run examples
    try:
        example_usage()
    except Exception as e:
        print(f"Error: {e}")
        exit(1)

# Made with Bob
