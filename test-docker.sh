#!/bin/bash

# Git-Vault Docker Testing Script
# This script provides various ways to test git-vault using Docker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Git-Vault Docker Testing Script"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  test        Run automated test suite"
    echo "  interactive Start interactive testing environment"
    echo "  build       Build Docker image only"
    echo "  clean       Clean up Docker containers and images"
    echo "  help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 test                    # Run full test suite"
    echo "  $0 interactive            # Start interactive shell"
    echo "  $0 build                  # Build image without running tests"
    echo
}

build_image() {
    print_info "Building git-vault Docker image..."
    docker-compose build git-vault-test
    print_success "Docker image built successfully"
}

run_tests() {
    print_info "Running git-vault automated test suite..."
    
    # Build and run tests
    docker-compose up --build git-vault-test
    
    # Check exit code
    if [ $? -eq 0 ]; then
        print_success "All tests passed!"
    else
        print_error "Some tests failed. Check output above."
        exit 1
    fi
}

run_interactive() {
    print_info "Starting interactive git-vault testing environment..."
    print_info "You can now test git-vault manually in the container."
    print_info "The git-vault source is available at /home/testuser/git-vault-source/"
    print_info "Type 'exit' to leave the container."
    echo
    
    # Start interactive container
    docker-compose run --rm git-vault-interactive
}

clean_docker() {
    print_info "Cleaning up Docker containers and images..."
    
    # Stop and remove containers
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
    
    # Remove images
    docker rmi git-vault_git-vault-test 2>/dev/null || true
    docker rmi git-vault_git-vault-interactive 2>/dev/null || true
    
    # Clean up unused volumes
    docker volume prune -f 2>/dev/null || true
    
    print_success "Docker cleanup completed"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
}

# Main script logic
main() {
    local command="${1:-help}"
    
    case "$command" in
        "test")
            check_docker
            run_tests
            ;;
        "interactive")
            check_docker
            run_interactive
            ;;
        "build")
            check_docker
            build_image
            ;;
        "clean")
            check_docker
            clean_docker
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"