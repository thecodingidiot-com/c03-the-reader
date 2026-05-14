NAME        = libidiot.a
FORGE       = libforge.a
CC          = gcc
CFLAGS      = -Wall -Wextra -g -std=c99 -D BUFFER_SIZE=32
AR          = ar rcs

SRCS        = il_memset.c il_memcpy.c il_memmove.c il_memchr.c il_bzero.c \
              il_calloc.c \
              il_isascii.c il_isalpha.c il_isdigit.c il_isalnum.c il_isspace.c \
              il_isupper.c il_islower.c il_isprint.c \
              il_toupper.c il_tolower.c \
              il_strlen.c il_strcpy.c il_strncpy.c \
              il_strlcpy.c il_strlcat.c \
              il_strcmp.c il_strncmp.c \
              il_strchr.c il_strrchr.c \
              il_strdup.c il_strndup.c il_strnstr.c il_atoi.c \
              il_printf.c \
              il_getline.c

FORGE_SRCS  = fg_split.c

OBJS        = $(SRCS:.c=.o)
FORGE_OBJS  = $(FORGE_SRCS:.c=.o)

.PHONY: all clean fclean re

all: $(NAME) $(FORGE)

$(NAME): $(OBJS)
	$(AR) $(NAME) $(OBJS)

$(FORGE): $(FORGE_OBJS)
	$(AR) $(FORGE) $(FORGE_OBJS)

%.o: %.c idiotlib.h
	$(CC) $(CFLAGS) -c $< -o $@

fg_split.o: fg_split.c forge.h idiotlib.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(FORGE_OBJS)

fclean: clean
	rm -f $(NAME) $(FORGE)

re: fclean all
