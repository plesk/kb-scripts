# Knowledge Base Article Scripts

This repository contains the scripts mentioned in various Plesk knowledge base articles.

# Structure

The repository structure is the following:

```
kb-scripts
├── ...
├── rebuild-awstats
│   ├── 213901965.kb
│   └── rebuild-awstats.sh
├── update-chroot
│   └── update-chroot.sh
└── ...
```

Each script is stored in a separate directory. Shell scripts should have .sh suffix in the file name. The reference to the corresponding KB article is implemented using empty file flags (e.g. `213901965.kb`)

# Contribution

Fill free to submit pull requests. Please follow [best practices](https://git-scm.com/book/en/v2/Distributed-Git-Contributing-to-a-Project). Scripts should be well tested, have "usage" block and clear explanation of applicability.
