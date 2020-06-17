provider "aws" {
  region = "us-east-2"
  profile = "poweruser"
}


// Step 1- Generating keys 

variable "key_name" {}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


// Step 2- creating a key pair in aws

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.key_name}"
  public_key = "${tls_private_key.example.public_key_openssh}"
}




variable "public_key"{
	default = "aws_key_pair.generated_key.key_name"
}

resource "local_file"  "private_key"{
 content = tls_private_key.example.private_key_pem
 filename = "privatekey.pem"

depends_on = [
    tls_private_key.example,
    aws_key_pair.generated_key	
]
}



// Step 3- creating security group

resource "aws_security_group" "terraform_ec2_sg" {
  name        = "allow_http"

  ingress {
    description = "allow http request"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "allow ssh request"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }  


  tags = {
    Name = "allow_http"
  }
}

//step 4 - downloading the images from git repo


resource "null_resource" "copying_images" {

  provisioner "local-exec"   {
    command = "echo git clone https://github.com/sudipti1234/wetsite.git"
  
  } 
}




// Step 5- creating a s3 bucket

resource "aws_s3_bucket" "lwbucket15" {
  bucket = "lwbucket15" 
   acl    = "public-read"
 
  tags = {
    Name        = "lwbucket15"
  }
  versioning {
	enabled =true
  }

}

// Step 6 - Creating bucket oblect
resource "aws_s3_bucket_object" "s3object" {
 depends_on = [
    aws_s3_bucket.lwbucket15,
  ]

   for_each = fileset ("C:/Users/sudipti/Desktop/terraform_code/task1/wetsite" , "**/*.jpg")
   content_type="image/jpeg"  
  bucket = "${aws_s3_bucket.lwbucket15.id}"
   key           = replace(each.value, "C:/Users/sudipti/Desktop/terraform_code/task1/wetsite", "")
  source = "C:/Users/sudipti/Desktop/terraform_code/task1/wetsite/${each.value}"
  acl    = "public-read" 
}


// Step 7- creating cloudfront 

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
depends_on = [
    aws_s3_bucket_object.s3object,
  ]
  comment = "This is origin access identity"
}

output "origin_access" {
value = aws_cloudfront_origin_access_identity.origin_access_identity
}

resource "aws_cloudfront_distribution" "bucket_distribution" {

 depends_on = [
    aws_cloudfront_origin_access_identity.origin_access_identity,
  ]

    origin {
       // domain_name = "lwbucket15.s3.amazonaws.com"
        origin_id = "S3-lwbucket15" 

   domain_name = "${aws_s3_bucket.lwbucket15.bucket_regional_domain_name}"



        s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
       
    enabled = true
      is_ipv6_enabled     = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-lwbucket15"


        # Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 10
        max_ttl = 30
    }
    //Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }


    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

output "details"{
	value  = aws_cloudfront_distribution.bucket_distribution.domain_name
}


// Step 8 - launching an instance


resource "aws_instance" "our-instance" {

depends_on = [
        aws_key_pair.generated_key,
  ]


  ami           = "ami-0a54aef4ef3b5f881"
  instance_type = "t2.micro"
  security_groups =  [ "${aws_security_group.terraform_ec2_sg.name}" ]
   key_name	= "${var.key_name}"
  


connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.our-instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
        "sudo yum install php  httpd git -y",
        "sudo systemctl enable httpd",
        "sudo systemctl start httpd",
 ]

}

  tags = {
    Name = "webserver"
  }
}


//Step 9 - creating an addtional ebs store

resource "aws_ebs_volume" "additional-vol" {
  availability_zone = aws_instance.our-instance.availability_zone
  size              = 1

   tags = {
    Name = "addtional-ebs"
  }
}

//Step 10 - attaching the instance with ebs

resource "aws_volume_attachment" "attaching-volume" {
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.additional-vol.id
  instance_id = aws_instance.our-instance.id
   force_detach = true
}



resource "null_resource" "save_ips"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.our-instance.public_ip} > publicip.txt"
  	}
}

//Step 10 - configuring web server 

resource "null_resource" "hosting-website"  {

depends_on = [
    aws_volume_attachment.attaching-volume,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.our-instance.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdd",
      "sudo mount  /dev/xvdd  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/sudipti1234/wetsite.git  /var/www/html/",
      "sudo su << EOF\"\n echo \"<img src='${aws_cloudfront_distribution.bucket_distribution.domain_name}'>\">> /var/www/html/index.html\n\"EOF\" sudo su << EOF",
	//"echo \"<img src='https://${aws_cloudfront_distribution.bucket_distribution.domain_name}/${aws_s3_bucket_object.s3object.lwbucket15.key}'>\">> /var/www/html/index.html","EOF",
      "sudo systemctl restart httpd ",
	]
  }

}


// Step 11 - Creating EBS snapshot

resource "aws_ebs_snapshot" "server_snapshot"{
    volume_id = aws_ebs_volume.additional-vol.id
    tags = {
	Name = "server_snapshot"
	}
}




