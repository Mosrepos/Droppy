// Droppy Marketing Site - JavaScript

document.addEventListener('DOMContentLoaded', function () {
    // Copy command to clipboard
    window.copyCommand = function () {
        const command = 'brew install --cask iordv/tap/droppy';
        navigator.clipboard.writeText(command).then(function () {
            const btn = document.getElementById('copy-btn');
            const copyIcon = document.getElementById('copy-icon');
            const checkIcon = document.getElementById('check-icon');

            copyIcon.classList.add('hidden');
            checkIcon.classList.remove('hidden');

            setTimeout(function () {
                copyIcon.classList.remove('hidden');
                checkIcon.classList.add('hidden');
            }, 2000);
        });
    };

    // Notch hover interaction
    const notch = document.getElementById('notch');
    if (notch) {
        notch.addEventListener('mouseenter', function () {
            this.classList.add('active');
        });

        notch.addEventListener('mouseleave', function () {
            this.classList.remove('active');
        });

        // Add click to toggle for mobile
        notch.addEventListener('click', function () {
            this.classList.toggle('active');
        });
    }

    // Scroll animations with Intersection Observer
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, observerOptions);

    // Observe all feature cards
    document.querySelectorAll('.feature-card').forEach(function (card) {
        card.classList.add('scroll-animate');
        observer.observe(card);
    });

    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // Header background on scroll
    const header = document.querySelector('header');
    let lastScroll = 0;

    window.addEventListener('scroll', function () {
        const currentScroll = window.pageYOffset;

        if (currentScroll > 50) {
            header.style.borderBottomColor = 'rgba(255, 255, 255, 0.1)';
        } else {
            header.style.borderBottomColor = 'rgba(255, 255, 255, 0.05)';
        }

        lastScroll = currentScroll;
    });

    // Add staggered animation delays to feature cards
    document.querySelectorAll('.feature-card').forEach(function (card, index) {
        card.style.transitionDelay = (index * 100) + 'ms';
    });

    // Animate hero elements on load
    setTimeout(function () {
        document.querySelectorAll('.animate-fade-in').forEach(function (el) {
            el.style.opacity = '1';
        });
    }, 100);
});

// Add hidden class utility
const style = document.createElement('style');
style.textContent = '.hidden { display: none !important; }';
document.head.appendChild(style);
