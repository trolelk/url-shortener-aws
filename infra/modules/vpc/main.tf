data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "url_shortener_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "public_subnets_url_shortener" {
  count                   = 2
  vpc_id                  = aws_vpc.url_shortener_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw_url_shortener" {
  vpc_id = aws_vpc.url_shortener_vpc.id
}

resource "aws_route_table" "rt_igw_shortener" {
  vpc_id = aws_vpc.url_shortener_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_url_shortener.id
  }
}

resource "aws_route_table_association" "rt_igw_asc_shortener" {
  count          = 2
  route_table_id = aws_route_table.rt_igw_shortener.id
  subnet_id      = aws_subnet.public_subnets_url_shortener[count.index].id
}
