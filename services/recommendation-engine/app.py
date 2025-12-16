"""
Recommendation Engine Service
- FastAPI service for ML-powered game recommendations
- Uses Redis for caching
- Uses Qdrant for vector similarity search
"""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

import redis
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import qdrant_client
from qdrant_client.models import Distance, VectorParams, PointStruct

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Recommendation Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Redis client
redis_client = None
try:
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'localhost'),
        port=int(os.getenv('REDIS_PORT', '6379')),
        db=int(os.getenv('REDIS_DB', '0')),
        decode_responses=True,
        socket_connect_timeout=5,
    )
    redis_client.ping()
    logger.info("Redis connection established")
except Exception as e:
    logger.warning(f"Redis connection failed: {e}")

# Qdrant client
qdrant_client_instance = None
try:
    qdrant_client_instance = qdrant_client.QdrantClient(
        host=os.getenv('QDRANT_HOST', 'localhost'),
        port=int(os.getenv('QDRANT_PORT', '6333')),
    )
    logger.info("Qdrant connection established")
except Exception as e:
    logger.warning(f"Qdrant connection failed: {e}")


class RecommendationRequest(BaseModel):
    player_id: str
    game_id: Optional[str] = None
    limit: int = 10


class RecommendationResponse(BaseModel):
    player_id: str
    recommendations: List[Dict[str, Any]]
    cached: bool
    generated_at: str


def get_redis():
    """Dependency for Redis client"""
    return redis_client


def get_qdrant():
    """Dependency for Qdrant client"""
    return qdrant_client_instance


@app.get("/health/live")
async def liveness():
    """Liveness probe"""
    return {"status": "alive"}


@app.get("/health/ready")
async def readiness():
    """Readiness probe"""
    if not redis_client:
        raise HTTPException(status_code=503, detail="Redis not available")
    return {"status": "ready"}


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    # Simple metrics endpoint
    return {
        "requests_total": 0,
        "cache_hits": 0,
        "cache_misses": 0,
    }


def generate_recommendations(player_id: str, game_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Generate game recommendations for a player
    
    This is a mock implementation. In production, this would:
    1. Fetch player's game history and preferences
    2. Use ML model to generate embeddings
    3. Search Qdrant for similar games
    4. Rank and filter results
    """
    # Mock recommendations
    recommendations = [
        {
            "game_id": "game-001",
            "title": "Epic Adventure",
            "score": 0.95,
            "reason": "Based on your play history",
        },
        {
            "game_id": "game-002",
            "title": "Strategy Master",
            "score": 0.87,
            "reason": "Similar players enjoyed this",
        },
        {
            "game_id": "game-003",
            "title": "Puzzle Quest",
            "score": 0.82,
            "reason": "Trending in your region",
        },
    ]
    
    return recommendations


@app.post("/api/v1/recommendations", response_model=RecommendationResponse)
async def get_recommendations(
    request: RecommendationRequest,
    redis: redis.Redis = Depends(get_redis)
):
    """Get game recommendations for a player"""
    
    cache_key = f"recommendations:{request.player_id}:{request.game_id or 'all'}"
    cached = False
    
    # Check cache
    if redis:
        try:
            cached_data = redis.get(cache_key)
            if cached_data:
                cached = True
                data = json.loads(cached_data)
                logger.info(f"Cache hit for player {request.player_id}")
                return RecommendationResponse(**data)
        except Exception as e:
            logger.warning(f"Redis error: {e}")
    
    # Generate recommendations
    recommendations = generate_recommendations(
        request.player_id,
        request.game_id
    )
    
    # Limit results
    recommendations = recommendations[:request.limit]
    
    response_data = {
        "player_id": request.player_id,
        "recommendations": recommendations,
        "cached": cached,
        "generated_at": datetime.utcnow().isoformat(),
    }
    
    # Cache for 1 hour
    if redis:
        try:
            redis.setex(
                cache_key,
                timedelta(hours=1),
                json.dumps(response_data)
            )
        except Exception as e:
            logger.warning(f"Failed to cache: {e}")
    
    return RecommendationResponse(**response_data)


@app.get("/api/v1/recommendations/{player_id}")
async def get_recommendations_simple(player_id: str):
    """Simple GET endpoint for recommendations"""
    request = RecommendationRequest(player_id=player_id)
    return await get_recommendations(request)


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8080")))



