statuscralwer
=============

Crawls all pages on a specified url, logs all statuses and mail a report.

Usage:

./statuscralwer.pl -l <levels> -m <mailadresses> http://yoursite.com/

* mailadresses is separated by comma.
* If you do not specify a level it will crawl the whole site.
* Will only crawl one level on urls outside your specified domain.
