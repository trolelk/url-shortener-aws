from pydantic import BaseModel, AnyHttpUrl

class ShortenRequest(BaseModel):
    url: AnyHttpUrl